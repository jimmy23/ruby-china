command = ARGV[0] || 'start'
current_path = File.expand_path('..',__FILE__)

%W[
	week_hot_score_subscribed.rb
	hours24_hot_score_subscribed.rb
].each do |task|
	system("ruby #{File.join(current_path,task)} #{command}")
end
