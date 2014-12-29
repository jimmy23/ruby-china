require File.expand_path('../../config/environment',__FILE__)
require 'rufus/scheduler'

s = Rufus::Scheduler.new

#每10分钟跑一次
def min10_active
    now = Time.now
    
    ids = $redis.smembers("10min_active_topics")
    $redis.expire("10min_active_topics",0)

    ids.each do |id|
      score = 0
      num = 24

      0.upto(23) do |i|
        date = (now - i.hour).to_date
        hour = (now - i.hour).hour
        readnum,replynum = 0,0

        readkey = "topic_#{id}_readnum_#{date}"
        readnum = $redis.hget(readkey,hour).to_i if $redis.hget(readkey,hour)

        replykey = "topic_#{id}_replynum_#{date}"
        replynum = $redis.hget(replykey,hour).to_i if $redis.hget(replykey,hour)
        
        score += (readnum + replynum * 3) * num
        num -= 1
      end

      t = Topic.find(id)
      t.hours24_score = score
      t.save
    end

end

#每一小时跑一次
def hours24_active
    now = Time.now
    
    topics = Topic.all

    topics.each do |t|
      score = 0
      num = 24

      0.upto(23) do |i|
        date = (now - i.hour).to_date
        hour = (now - i.hour).hour
        readnum,replynum = 0,0

        readkey = "topic_#{t.id}_readnum_#{date}"
        readnum = $redis.hget(readkey,hour).to_i if $redis.hget(readkey,hour)

        replykey = "topic_#{t.id}_replynum_#{date}"
        replynum = $redis.hget(replykey,hour).to_i if $redis.hget(replykey,hour)
        
        score += (readnum + replynum * 3) * num
        num -= 1
      end

      t.hours24_score = score
      t.save
    end
end

begin
  logger ||= Logger.new(File.join(File.expand_path("../../log", __FILE__), 'hours24_hot_score.log'))

  s.every '10m' do
      logger.info "start min10_active"
      min10_active
      logger.info "end min10_active"
  end

  s.every '1h' do
      logger.info "start hours24_active"
      hours24_active
      logger.info "end hours24_active"
  end
rescue  => e
  logger_error ||= Logger.new(File.join(File.expand_path("../../log", __FILE__), 'hours24_hot_score_error.log'))
  logger_error.info Time.now
  logger_error.info "#{e.class} #{e.message}"
  logger_error.info e.backtrace.join("\n")
end

s.join