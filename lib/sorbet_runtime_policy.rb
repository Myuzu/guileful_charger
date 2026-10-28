# Report Sorbet's supported failures without logging inspected values or error
# messages. Ruby exceptions inside sig blocks and inline assertions still raise.
module SorbetRuntimePolicy
  class Reporter
    INTERVAL = 60
    MAX_KEYS = 1000
    MODULE_NAME = Module.instance_method(:name)
    OBJECT_CLASS = Kernel.instance_method(:class)

    def initialize(logger, clock)
      @logger = logger
      @clock = clock
      @reported = {}
      @lock = Mutex.new
    end

    def report(kind:, method: nil, location: nil, name: nil)
      if !method && name
        # T::Props supplies a property name but no owner/signature. Its caller
        # can point into a versioned runtime gem; retain the first external frame.
        location = caller_locations.find do |frame|
          frame.path != __FILE__ && !frame.path.match?(%r{/sorbet-runtime(?:-[^/]+)?/lib/})
        end || location
      end
      label = method ? method_label(method) : (name ? "property##{name}" : "unknown method")
      source = source_label(location || method&.source_location)
      key = [ label, kind, method.nil? ? source : nil ]
      now = @clock.call
      emit = @lock.synchronize do
        previous = @reported[key]
        next false if previous && now - previous < INTERVAL

        @reported.clear if @reported.size >= MAX_KEYS && !@reported.key?(key)
        @reported[key] = now
        true
      end
      return unless emit

      @logger.error("Sorbet #{kind}: #{label}#{source ? " at #{source}" : ''}")
    rescue StandardError
      # Reporting must not turn a type violation into a billing failure. Avoid a
      # fallback logger here: it could fail recursively or expose error values.
      nil
    end

    private

    def method_label(method)
      owner = method.owner
      if owner.singleton_class?
        attached = owner.attached_object
        klass = Module === attached ? attached : OBJECT_CLASS.bind_call(attached)
        name = MODULE_NAME.bind_call(klass)
        "#{name || '(anonymous)'}.#{method.name}"
      else
        "#{MODULE_NAME.bind_call(owner) || '(anonymous)'}##{method.name}"
      end
    end

    def source_label(location)
      case location
      when Thread::Backtrace::Location
        "#{location.path}:#{location.lineno}"
      when Array
        location.join(":")
      end
    end
  end

  def self.configure(production:, logger:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    return unless production

    reporter = Reporter.new(logger, clock)
    T::Configuration.call_validation_error_handler = lambda do |signature, options|
      reporter.report(kind: options[:kind], method: signature&.method, location: options[:location], name: options[:name])
    end
    T::Configuration.sig_builder_error_handler = lambda do |_error, location|
      reporter.report(kind: "sig builder", location: location)
    end
    T::Configuration.sig_validation_error_handler = lambda do |_error, options|
      reporter.report(kind: "sig validation", method: options[:method])
    end
  end
end
