autoloader = Rails.autoloaders.main

Dir.glob(File.join("app/consumers", "*_consumer.rb")).each do |consumer|
  autoloader.preload(consumer)
end
