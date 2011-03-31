require 'resque'

module ResqueSpec
  extend self

  def in_queue?(klass, *args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    queue = options[:queue_name] ? queues[options[:queue_name]] : queue_for(klass)
    queue.any? {|entry| entry[:klass].to_s == klass.to_s && entry[:args] == args}
  end

  def queue_for(klass)
    queues[queue_name(klass)]
  end

  def queue_name(klass)
    klass = ::Resque.constantize(klass) rescue nil if klass.is_a?(String)
    name_from_instance_var(klass) or
      name_from_queue_accessor(klass) or
        raise ::Resque::NoQueueError.new("Jobs must be placed onto a queue.")
  end

  def queue_size(klass)
    queue_for(klass).size
  end

  def queues
    @queues ||= Hash.new {|h,k| h[k] = []}
  end

  def reset!
    queues.clear
  end
  
  private

    def name_from_instance_var(klass)
      klass.instance_variable_get(:@queue)
    end

    def name_from_queue_accessor(klass)
      klass.respond_to?(:queue) and klass.queue
    end  

  module Resque
    extend self

    def reset!
      ResqueSpec.reset!
    end  
    
    def run!(queue = nil)
      if queue
        ResqueSpec.queues[queue].each do |payload|
          job = ::Resque::Job.new(queue, 'class' => payload[:klass], 'args' => payload[:args])
          job.perform          
        end
      else
        ResqueSpec.queues.each do |queue, payloads|
          payloads.each do |payload|
            job = ::Resque::Job.new(queue, 'class' => payload[:klass], 'args' => payload[:args])
            job.perform                      
          end
        end
      end
    end
      
    module Job
      extend self
      
      def self.included(base)
        base.instance_eval do
          
          def create_without_resque(queue, klass, *args)
            raise ::Resque::NoQueueError.new("Jobs must be placed onto a queue.") if !queue
            raise ::Resque::NoClassError.new("Jobs must be given a class.") if klass.to_s.empty?
            ResqueSpec.queues[queue] << {:klass => klass.to_s, :args => args}
          end
          alias :create_with_resque :create
          alias :create :create_without_resque       

          def destroy_without_resque(queue, klass, *args)
            raise ::Resque::NoQueueError.new("Jobs must have been placed onto a queue.") if !queue
            raise ::Resque::NoClassError.new("Jobs must have been given a class.") if klass.to_s.empty?

            old_count = ResqueSpec.queues[queue].size

            if args.empty?
              ResqueSpec.queues[queue].delete_if{ |job| job[:klass] == klass.to_s }
            else
              ResqueSpec.queues[queue].delete_if{ |job| job[:klass] == klass.to_s and job[:args].to_a == args.to_a }
            end
            old_count - ResqueSpec.queues[queue].size
          end    
          alias :destroy_with_resque :destroy
          alias :destroy :destroy_without_resque          
          
        end
      end    
      
    end
        
  end
end

Resque.extend ResqueSpec::Resque
Resque::Job.send :include, ResqueSpec::Resque::Job
