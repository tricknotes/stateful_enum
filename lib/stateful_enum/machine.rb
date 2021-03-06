module StatefulEnum
  class Machine
    def initialize(model, column, states, prefix, suffix, &block)
      @model, @column, @states, @event_names = model, column, states, []
      @prefix = if prefix == true
                  "#{column}_"
                elsif prefix
                  "#{prefix}_"
                end
      @suffix = if suffix == true
                  "_#{column}"
                elsif suffix
                  "_#{suffix}"
                end

      # undef non-verb methods e.g. Model#active!
      states.each do |state|
        @model.send :undef_method, "#{@prefix}#{state}#{@suffix}!"
      end

      instance_eval(&block) if block
    end

    def event(name, &block)
      raise "event: :#{name} has already been defined." if @event_names.include? name
      Event.new @model, @column, @states, @prefix, @suffix, name, &block
      @event_names << name
    end

    class Event
      def initialize(model, column, states, prefix, suffix, name, &block)
        @model, @column, @states, @prefix, @suffix, @name, @transitions, @before, @after = model, column, states, prefix, suffix, name, {}, nil, nil

        instance_eval(&block) if block

        define_transition_methods
      end

      def transition(transitions, options = {})
        if options.blank?
          options[:if] = transitions.delete :if
          #TODO should err if if & unless were specified together?
          if (unless_condition = transitions.delete :unless)
            options[:if] = -> { !instance_exec(&unless_condition) }
          end
        end
        transitions.each_pair do |from, to|
          raise "Undefined state #{to}" unless @states.include? to
          Array(from).each do |f|
            raise "Undefined state #{f}" unless @states.include? f
            raise "Duplicate entry: Transition from #{f} to #{@transitions[f].first} has already been defined." if @transitions[f]
            @transitions[f] = [to, options[:if]]
          end
        end
      end

      def all
        @states
      end

      def before(&block)
        @before = block
      end

      def after(&block)
        @after = block
      end

      private def define_transition_methods
        column, prefix, suffix, name, transitions, before, after = @column, @prefix, @suffix, @name, @transitions, @before, @after
        new_method_name = "#{prefix}#{name}#{suffix}"

        @model.send(:define_method, new_method_name) do
          to, condition = transitions[self.send(column).to_sym]
          #TODO better error
          if to && (!condition || instance_exec(&condition))
            #TODO transaction?
            instance_eval(&before) if before
            original_method = self.class.send(:_enum_methods_module).instance_method "#{prefix}#{to}#{suffix}!"
            ret = original_method.bind(self).call
            instance_eval(&after) if after
            ret
          else
            false
          end
        end

        @model.send(:define_method, "#{new_method_name}!") do
          send(new_method_name) || raise('Invalid transition')
        end

        @model.send(:define_method, "can_#{new_method_name}?") do
          transitions.has_key? self.send(column).to_sym
        end

        @model.send(:define_method, "#{new_method_name}_transition") do
          transitions[self.send(column).to_sym].try! :first
        end
      end
    end
  end
end
