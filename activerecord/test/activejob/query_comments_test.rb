# frozen_string_literal: true

require "activejob/helper"
require "active_record/railties/query_comments"
require "models/dashboard"

class DashboardJob < ActiveJob::Base
  def perform
    Dashboard.first
  end
end

# This config var is added in the railtie
class ActiveJob::Base
  mattr_accessor :query_comments_action_filter_enabled, instance_accessor: false, default: true
end

ActiveJob::Base.include(ActiveRecord::Railties::QueryComments::ActiveJob)

class ActiveJobQueryCommentsTest < ActiveRecord::TestCase
  include ActiveJob::TestHelper

  def setup
    @original_enabled = ActiveRecord::Base.query_comments_enabled
    @original_components = comment_context.components
    if @original_enabled == false
      # if we haven't enabled the feature, the execution methods need to be prepended at run time
      ActiveRecord::Base.connection.class_eval do
        prepend(ActiveRecord::ConnectionAdapters::QueryComment::ExecutionMethods)
      end
    end
    ActiveRecord::Base.query_comments_enabled = true
    @original_application_name = comment_context.send(:context)[:application_name]
    comment_context.update(application_name: "active_record")
    comment_context.components = [:job]
  end

  def teardown
    ActiveRecord::Base.query_comments_enabled = @original_enabled
    comment_context.components = @original_components
    comment_context.update(application_name: @original_application_name)
  end

  def comment_context
    ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext
  end

  def test_active_job
    assert_sql(%r{/\*job:DashboardJob\*/}) do
      DashboardJob.perform_later
      perform_enqueued_jobs
    end
  end
end
