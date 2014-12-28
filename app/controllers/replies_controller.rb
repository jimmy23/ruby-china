# coding: utf-8
class RepliesController < ApplicationController
  load_and_authorize_resource :reply

  before_filter :find_topic

  def create
    @reply = Reply.new(reply_params)
    @reply.topic_id = @topic.id
    @reply.user_id = current_user.id

    if @reply.save
      current_user.read_topic(@topic)
      @msg = t('topics.reply_success')
      #记录某天某小时topic回复数到redis
      set_replynum_to_redis
    else
      @msg = @reply.errors.full_messages.join('<br />')
    end
  end

  def edit
    @reply = Reply.find(params[:id])
  end

  def update
    @reply = Reply.find(params[:id])

    if @reply.update_attributes(reply_params)
      redirect_to(topic_path(@reply.topic_id), notice: '回帖更新成功。')
    else
      render action: 'edit'
    end
  end

  def destroy
    @reply = Reply.find(params[:id])
    if @reply.destroy
      redirect_to(topic_path(@reply.topic_id), notice: '回帖删除成功。')
    else
      redirect_to(topic_path(@reply.topic_id), alert: '程序异常，删除失败。')
    end
  end

  protected

  def find_topic
    @topic = Topic.find(params[:topic_id])
  end

  def reply_params
    params.require(:reply).permit(:body)
  end

  def set_replynum_to_redis
    now = Time.now
    str_date = now.to_date.to_s
    str_hour = now.hour.to_s

    #查询此topic的key是否存在
    key = $redis.get("topic_#{@topic.id}_replynum_#{str_date}")
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
      $redis.set("topic_#{@topic.id}_replynum_#{str_date}",JSON.dump(topic))
      $redis.expire("topic_#{@topic.id}_replynum_#{str_date}",604800)
    else
      topic_hash = {"#{str_hour}" => 1}

      $redis.set("topic_#{@topic.id}_replynum_#{str_date}",JSON.dump(topic_hash))
      $redis.expire("topic_#{@topic.id}_replynum_#{str_date}",604800)
    end
  end
end
