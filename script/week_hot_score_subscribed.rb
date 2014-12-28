require 'daemons'

Daemons.run(File.expand_path('../week_hot_score_scheduler.rb',__FILE__))