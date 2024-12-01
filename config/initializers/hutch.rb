Hutch::Config.load_from_file("config/hutch.yaml")

begin
  Hutch.connect
rescue Hutch::ConnectionError => ex
  Rails.logger.warn("Hutch::ConnectionError: #{ex}")
end
