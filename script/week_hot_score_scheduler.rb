require File.expand_path('../../config/environment',__FILE__)
require 'rufus/scheduler'

s = Rufus::Scheduler.new

def week_active
    now= Time.now.to_date

    topics = Topic.all

    topics.each do |t|
      score = 0
      num = 7

      0.upto(6) do |i|
        date = now - i.day
        readsum,replysum = 0,0

        readkey = "topic_#{t.id}_readnum_#{date}"
        readsum = $redis.hvals(readkey).map(&:to_i).reduce(:+) unless $redis.hlen(readkey) == 0
        replykey = "topic_#{t.id}_replynum_#{date}"
        replysum = $redis.hvals(replykey).map(&:to_i).reduce(:+)  unless $redis.hlen(replykey) == 0

        score += (readsum + replysum * 3) * num
        num -= 1
      end

      t.week_score = score
      t.save
    end
end

def hour_active
  now = Time.now.to_date

  ids = $redis.smembers("hour_active_topics")
  $redis.expire("hour_active_topics",0)

  ids.each do |id|
    score = 0
    num = 7

    0.upto(6) do |i|
      date = now - i.day
      readsum,replysum = 0,0

      readkey = "topic_#{id}_readnum_#{date}"
      readsum = $redis.hvals(readkey).map(&:to_i).reduce(:+) unless $redis.hlen(readkey) == 0
      replykey = "topic_#{id}_replynum_#{date}"
      replysum = $redis.hvals(replykey).map(&:to_i).reduce(:+) unless $redis.hlen(replykey) == 0

      score += (readsum + replysum * 3) * num
      num -= 1
    end

    t = Topic.find(id)
    t.week_score = score
    t.save
  end

end

# week_active
# hour_active

begin
  logger ||= Logger.new(File.join(File.expand_path("../../log", __FILE__), 'week_hot_score.log'))

  s.cron '59 23 * * *' do
    logger.info "start week active"
    week_active
    logger.info "end week active"
  end

  s.every '1h' do
    logger.info "start hour_active"
    hour_active
    logger.info "end hour_active"
  end
rescue  => e
  logger_error ||= Logger.new(File.join(File.expand_path("../../log", __FILE__), 'week_hot_score_error.log'))
  logger_error.info Time.now
  logger_error.info "#{e.class} #{e.message}"
  logger_error.info e.backtrace.join("\n")
end

s.join