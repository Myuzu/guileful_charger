require Rails.root.join("lib/rabbit_mq_topology")

Hutch::Config.load_from_file("config/hutch.yaml")

begin
  unless Rails.env.test?
    Hutch.connect
    RabbitMqTopology.declare!
  end
rescue Hutch::ConnectionError => ex
  Rails.logger.warn("Hutch::ConnectionError: #{ex}")
end
