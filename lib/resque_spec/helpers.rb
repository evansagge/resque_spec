module ResqueSpec
  module Helpers

    def with_resque
      enable_perform
      yield
      disable_perform
    end

    private

    def enable_perform
      ::Resque.module_eval do
        def self.enqueue(klass, *args)
          job = ::Resque::Job.new(ResqueSpec.queue_name(klass), 'class' => klass.to_s, 'args' => args)
          job.perform
        end
      end
    end

    def disable_perform
      ::Resque.module_eval do
        def self.enqueue(klass, *args)
          ::Resque::Job.create(ResqueSpec.queue_name(klass), klass, *args)
        end
      end
    end
  end
end
