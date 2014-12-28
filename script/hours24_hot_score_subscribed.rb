require 'daemons'

Daemons.run(File.expand_path('../hours24_hot_score_scheduler.rb',__FILE__))