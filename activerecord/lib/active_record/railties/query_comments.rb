# frozen_string_literal: true

module ActiveRecord
  module Railties # :nodoc:
    module QueryComments #:nodoc:
      module ActionController
        extend ActiveSupport::Concern

        included do
          if ::ActionController::Base.query_comments_action_filter_enabled
            around_action :record_query_comment
          end
          ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.include(ControllerContext)
        end

        def record_query_comment
          ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.update(controller: self)
          yield
        ensure
          ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.update(controller: nil)
        end

        module ControllerContext # :nodoc:
          extend ActiveSupport::Concern

          module ClassMethods # :nodoc:
            def controller
              context[:controller]&.controller_name
            end

            def controller_with_namespace
              context[:controller]&.class&.name
            end

            def action
              context[:controller]&.action_name
            end
          end
        end
      end

      module ActiveJob
        extend ActiveSupport::Concern

        included do
          if ::ActiveJob::Base.query_comments_action_filter_enabled
            ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.components << :job
            around_perform do |job, block|
              ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.update(job: job)
              block.call
            ensure
              ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.update(job: nil)
            end
          end
          ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext.include(JobContext)
        end

        module JobContext
          extend ActiveSupport::Concern
          module ClassMethods
            def job
              context[:job]&.class&.name
            end
          end
        end
      end
    end
  end
end
