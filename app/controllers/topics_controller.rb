# coding: utf-8
require 'json'

class TopicsController < ApplicationController
  load_and_authorize_resource only: [:new, :edit, :create, :update, :destroy,
                                     :favorite, :unfavorite, :follow, :unfollow, :suggest, :unsuggest]
  caches_action :feed, :node_feed, expires_in: 1.hours

  def index
    @suggest_topics = Topic.without_hide_nodes.suggest.limit(3)
    suggest_topic_ids = @suggest_topics.map(&:id)

    @topics = Topic.last_actived.without_hide_nodes.where(:_id.nin => suggest_topic_ids)
    @topics = @topics.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)

    set_seo_meta t("menu.topics"), "#{Setting.app_name}#{t("menu.topics")}"
  end

  def feed
    @topics = Topic.recent.without_body.limit(20).includes(:node, :user, :last_reply_user)
    render layout: false
  end

  def node
    @node = Node.find(params[:id])
    @topics = @node.topics.last_actived.fields_for_list
    @topics = @topics.includes(:user).paginate(page: params[:page], per_page: 15)
    title = @node.jobs? ? @node.name : "#{@node.name} &raquo; #{t("menu.topics")}"
    set_seo_meta title, "#{Setting.app_name}#{t("menu.topics")}#{@node.name}", @node.summary
    render action: 'index'
  end

  def node_feed
    @node = Node.find(params[:id])
    @topics = @node.topics.recent.without_body.limit(20)
    render layout: false
  end

  %W(no_reply popular).each do |name|
    define_method(name) do
      @topics = Topic.send(name.to_sym).last_actived.fields_for_list.includes(:user)
      @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)

      set_seo_meta [t("topics.topic_list.#{name}"), t('menu.topics')].join(' &raquo; ')
      render action: 'index'
    end
  end

  def recent
    @topics = Topic.recent.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)
    set_seo_meta [t('topics.topic_list.recent'), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  def excellent
    @topics = Topic.excellent.recent.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)

    set_seo_meta [t('topics.topic_list.excellent'), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  def show
    @topic = Topic.without_body.find(params[:id])
    @topic.hits.incr(1)
    @node = @topic.node
    @show_raw = params[:raw] == '1'

    @per_page = Reply.per_page
    # 默认最后一页
    params[:page] = @topic.last_page_with_per_page(@per_page) if params[:page].blank?
    @page = params[:page].to_i > 0 ? params[:page].to_i : 1

    @replies = @topic.replies.unscoped.without_body.asc(:_id)
    @replies = @replies.paginate(page: @page, per_page: @per_page)
    
    check_current_user_status_for_topic
    set_special_node_active_menu
    #记录某天某小时阅读数到redis
    set_readnum_to_redis

    set_seo_meta "#{@topic.title} &raquo; #{t("menu.topics")}"

    fresh_when(etag: [@topic, @has_followed, @has_favorited, @replies, @node, @show_raw])
  end

  def set_readnum_to_redis
    now = Time.now
    str_date = now.to_date.to_s
    str_hour = now.hour.to_s

    #查询此topic的key是否存在
    key = $redis.get("topic_#{@topic.id}_readnum_#{str_date}")
    if key
      topic = JSON.load(key)
      
      #小时时间段
      hour = topic["#{str_hour}"]
      #小时时间段里存在，直接加1，不存在则赋值1
      if hour
        topic["#{str_hour}"] += 1
      else
        topic["#{str_hour}"] = 1
      end     

      #更新key,设置过期时间为7天后
      $redis.set("topic_#{@topic.id}_readnum_#{str_date}",JSON.dump(topic))
      $redis.expire("topic_#{@topic.id}_readnum_#{str_date}",604800)
    else
      topic_hash = {"#{str_hour}" => 1}

      $redis.set("topic_#{@topic.id}_readnum_#{str_date}",JSON.dump(topic_hash))
      $redis.expire("topic_#{@topic.id}_readnum_#{str_date}",604800)
    end
  end
  
  def check_current_user_status_for_topic
    return false if not current_user
    
    # 找出用户 like 过的 Reply，给 JS 处理 like 功能的状态
    @user_liked_reply_ids = []
    @replies.each { |r| @user_liked_reply_ids << r.id if r.liked_user_ids.index(current_user.id) != nil }
    # 通知处理
    current_user.read_topic(@topic)
    # 是否关注过
    @has_followed = @topic.follower_ids.index(current_user.id) == nil
    # 是否收藏
    @has_favorited = current_user.favorite_topic_ids.index(@topic.id) == nil
  end
  
  def set_special_node_active_menu
    case @node.try(:id)
    when Node.jobs_id
      @current = ["/jobs"]
    end
  end

  def new
    @topic = Topic.new
    if !params[:node].blank?
      @topic.node_id = params[:node]
      @node = Node.find_by_id(params[:node])
      render_404 if @node.blank?
    end

    set_seo_meta "#{t('topics.post_topic')} &raquo; #{t('menu.topics')}"
  end

  def edit
    @topic = Topic.find(params[:id])
    @node = @topic.node

    set_seo_meta "#{t('topics.edit_topic')} &raquo; #{t('menu.topics')}"
  end

  def create
    @topic = Topic.new(topic_params)
    @topic.user_id = current_user.id
    @topic.node_id = params[:node] || topic_params[:node_id]

    if @topic.save
      redirect_to(topic_path(@topic.id), notice: t('topics.create_topic_success'))
    else
      render action: 'new'
    end
  end

  def preview
    @body = params[:body]

    respond_to do |format|
      format.json
    end
  end

  def update
    @topic = Topic.find(params[:id])
    if @topic.lock_node == false || current_user.admin?
      # 锁定接点的时候，只有管理员可以修改节点
      @topic.node_id = topic_params[:node_id]

      if current_user.admin? && @topic.node_id_changed?
        # 当管理员修改节点的时候，锁定节点
        @topic.lock_node = true
      end
    end
    @topic.title = topic_params[:title]
    @topic.body = topic_params[:body]

    if @topic.save
      redirect_to(topic_path(@topic.id), notice: t('topics.update_topic_success'))
    else
      render action: 'edit'
    end
  end

  def destroy
    @topic = Topic.find(params[:id])
    @topic.destroy_by(current_user)
    redirect_to(topics_path, notice: t('topics.delete_topic_success'))
  end

  def favorite
    current_user.favorite_topic(params[:id])
    render text: '1'
  end
  
  def unfavorite
    current_user.unfavorite_topic(params[:id])
    render text: '1'
  end

  def follow
    @topic = Topic.find(params[:id])
    @topic.push_follower(current_user.id)
    render text: '1'
  end

  def unfollow
    @topic = Topic.find(params[:id])
    @topic.pull_follower(current_user.id)
    render text: '1'
  end

  def suggest
    @topic = Topic.find(params[:id])
    @topic.update_attributes(excellent: 1)
    redirect_to @topic, success: '加精成功。'
  end

  def unsuggest
    @topic = Topic.find(params[:id])
    @topic.update_attribute(:excellent, 0)
    redirect_to @topic, success: '加精已经取消。'
  end

  #一周热门
  def week_hot
    @topics = Topic.week_score.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 10, total_entries: 100)

    set_seo_meta [t("topics.topic_list.week_hot"), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  #24小时热门
  def hours24_hot
    @topics = Topic.hours24_score.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 10, total_entries: 100)

    set_seo_meta [t("topics.topic_list.hours24_hot"), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  private

  def topic_params
    params.require(:topic).permit(:title, :body, :node_id)
  end  
end
