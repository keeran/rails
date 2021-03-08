# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors_per_thread"

module ActiveRecord
  module ConnectionAdapters
    module QueryComment
      extend ActiveSupport::Concern
      included do
        mattr_accessor :prepend_comment, default: false
      end

      module ClassMethods
        def prepend_execution_methods # :nodoc:
          descendants.each do |klass|
            # Prepend execution methods for edge descendants of AbstractAdapter
            klass.prepend(ExecutionMethods) if klass.descendants.empty?
          end
        end

        def add_query_comment_to_sql(sql) # :nodoc:
          return sql unless QueryCommentContext.comments_available?
          comments = [QueryCommentContext.comment, QueryCommentContext.inline_comment].compact
          comments.each do |comment|
            if comment.present? && !sql.include?(comment)
              sql = if prepend_comment
                "#{comment} #{sql}"
              else
                "#{sql} #{comment}"
              end
            end
          end
          sql
        end
      end

      module ExecutionMethods
        def execute(*args, **kwargs)
          sql, *rest = args
          sql = self.class.add_query_comment_to_sql(sql)
          args = rest.unshift(sql)
          super(*args, **kwargs)
        end

        def exec_query(*args, **kwargs)
          sql, *rest = args
          sql = self.class.add_query_comment_to_sql(sql)
          args = rest.unshift(sql)
          super(*args, **kwargs)
        end
      end

      # Maintains a user-defined context for all queries and constructs an SQL comment by
      # calling methods listed in +components+
      #
      # Additional information can be added to the context to be referenced by methods
      # defined in framework or application initializers.
      #
      # To add new comment components, define class methods on +QueryCommentContext+ in
      # your application.
      #
      #    module ActiveRecord::ConnectionAdapters::QueryComment::QueryCommentContext
      #      class << self
      #        def custom_component
      #          "custom value"
      #        end
      #      end
      #    end
      #    ActiveRecord::ConnectionAdapters::QueryComment::QueryCommentContext.components = []:custom_component]
      #    ActiveRecord::ConnectionAdapters::QueryComment::QueryCommentContext.comment
      #    # /*custom_component:custom value*/
      #
      # Default components available for use:
      #
      # * +application+
      # * +pid+
      # * +socket+
      # * +db_host+
      # * +database+
      # * +line+ (reported via BacktraceCleaner)
      #
      # _When included in Rails, ActiveController and ActiveJob components are also defined._
      #
      # * +controller+
      # * +action+
      # * +job+
      #
      # If required due to log truncation, comments can be prepended to the query instead:
      #
      #    ActiveRecord::ConnectionAdapters::QueryComment.prepend_comment = true


      module QueryCommentContext
        mattr_accessor :components, instance_accessor: false, default: [:application]
        mattr_accessor :cache_query_comment, instance_accessor: false, default: true
        mattr_accessor :backtrace_cleaner, default: ActiveSupport::BacktraceCleaner.new
        thread_mattr_accessor :cached_comment, instance_accessor: false

        class << self
          # Updates the context used to construct the query comment.
          # Resets the cached comment if <tt>cache_query_comment</tt> is +true+.
          def update(ctx)
            return unless ctx.is_a? Hash
            self.context.merge!(ctx.symbolize_keys)
            self.cached_comment = nil
          end

          def comments_available?
            self.components.present? || self.inline_annotations.present?
          end

          # Returns a +String+ containing the component-based query comment.
          # Sets and returns a cached comment if <tt>cache_query_comment</tt> is +true+.
          def comment
            return uncached_comment unless cache_query_comment
            return cached_comment unless cached_comment.nil?
            self.cached_comment = uncached_comment
          end

          def uncached_comment
            "/*#{escape_sql_comment(comment_content)}*/"
          end

          # Returns a +String+ containing any inline comments from +with_annotation+.
          def inline_comment
            return nil unless inline_annotations.present?
            "/*#{escape_sql_comment(inline_comment_content)}*/"
          end

          # Manually clear the comment cache.
          def clear_comment_cache!
            self.cached_comment = nil
          end

          # Annotate any query within `&block`. Can be nested.
          def with_annotation(comment, &block)
            self.inline_annotations.push(comment)
            block.call if block.present?
          ensure
            self.inline_annotations.pop
          end

          # Return the set of active inline annotations from +with_annotation+.
          def inline_annotations
            context[:inline_annotations] ||= []
          end

          # QueryComment +component+ methods

          # Set during Rails boot in lib/active_record/railtie.rb
          def application # :nodoc:
            context[:application_name]
          end

          def pid # :nodoc:
            Process.pid
          end

          def connection_config # :nodoc:
            ActiveRecord::Base.connection_db_config
          end

          def socket # :nodoc:
            connection_config.socket
          end

          def db_host # :nodoc:
            connection_config.host
          end

          def database # :nodoc:
            connection_config.database
          end

          def line # :nodoc:
            backtrace_cleaner.add_silencer { |line| line.match?(/lib\/active_(record|support)/) }
            backtrace_cleaner.clean(caller.lazy).first
          end

          private
            def context
              Thread.current[:active_record_query_comment_context] ||= {}
            end

            def escape_sql_comment(str)
              return str unless str.include?("*")
              while str.include?("/*") || str.include?("*/")
                str = str.gsub("/*", "").gsub("*/", "")
              end
              str
            end

            def comment_content
              components.filter_map do |c|
                if value = send(c)
                  "#{c}:#{value}"
                end
              end.join(",")
            end

            def inline_comment_content
              inline_annotations.join
            end
        end
      end
      delegate :cache_query_comment, to: QueryCommentContext
    end
  end
end
