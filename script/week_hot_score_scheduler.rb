require File.expand_path('../../config/environment',__FILE__)
require 'rufus/scheduler'
require 'json'

s = Rufus::Scheduler.new

def compute_week_hot_score
    today = Time.now.to_date

    topics = Topic.all
    topics.each do |t|
      score = 0
      num = 7

      0.upto(6) do |i|
        str_date = (today - i.day).to_s
        # puts "date: #{str_date}, i: #{i}"
        readsum,replysum = 0,0
        readkey = $redis.get("topic_#{t.id}_readnum_#{str_date}")
        if readkey
          readdata = JSON.load(readkey)
          readsum = readdata.values.reduce(:+)
        end
        replykey = $redis.get("topic_#{t.id}_replynum_#{str_date}")
        if replykey
          replydata = JSON.load(replykey)
          replysum = replydata.values.reduce(:+)
        end

        score += (readsum + replysum * 3) * num
        num -= 1
      end

      # puts score
      t.week_score = score
      t.save
    end
end

s.every '1h' do
  begin
    logger ||= Logger.new(File.join(File.expand_path("../../log", __FILE__), 'week_hot_score.log'))
    logger.info "start"
    compute_week_hot_score
    logger.info "end"
  rescue  => e
    logger_error ||= Logger.new(File.join(File.expand_path("../../log", __FILE__), 'week_hot_score_error.log'))
    logger_error.info Time.now
    logger_error.info "#{e.class} #{e.message}"
    logger_error.info e.backtrace.join("\n")
  end
end

s.join