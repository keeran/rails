# frozen_string_literal: true

require "cases/helper"
require "action_controller"
require "active_record/railties/query_comments"
require "models/dashboard"

class DashboardController < ActionController::Base
  def index
    @dashboard = Dashboard.first
    render body: nil
  end
end

class DashboardApiController < ActionController::API
  def index
    render json: Dashboard.all
  end
end

# This config var is added in the railtie
class ActionController::Base
  mattr_accessor :query_comments_action_filter_enabled, instance_accessor: false, default: true
end

ActionController::Base.include(ActiveRecord::Railties::QueryComments::ActionController)
ActionController::API.include(ActiveRecord::Railties::QueryComments::ActionController)

class ActionControllerQueryCommentsTest < ActiveRecord::TestCase
  def setup
    @env = Rack::MockRequest.env_for("/")
    @original_components = comment_context.components
    @default_components = comment_context.components = [:application, :controller, :action]
    @original_enabled = ActiveRecord::Base.query_comments_enabled
    if @original_enabled == false
      # if we haven't enabled the feature, the execution methods need to be prepended at run time
      ActiveRecord::Base.connection.class_eval do
        prepend(ActiveRecord::ConnectionAdapters::QueryComment::ExecutionMethods)
      end
    end
    ActiveRecord::Base.query_comments_enabled = true
    @original_application_name = comment_context.send(:context)[:application_name]
    comment_context.update(application_name: "active_record")
  end

  def teardown
    comment_context.components = @original_components
    ActiveRecord::Base.query_comments_enabled = @original_enabled
    comment_context.update(application_name: @original_application_name)
  end

  def comment_context
    ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryCommentContext
  end

  def test_default_components_are_added_to_comment
    assert_sql(%r{/\*application:active_record,controller:dashboard,action:index\*/}) do
      DashboardController.action(:index).call(@env)
    end
  end

  def test_configuring_query_comment_components
    comment_context.components = [:controller]

    assert_sql(%r{/\*controller:dashboard\*/}) do
      DashboardController.action(:index).call(@env)
    end
  ensure
    comment_context.components = @default_components
  end

  def test_api_controller_includes_comments
    comment_context.components = [:controller]

    assert_sql(%r{/\*controller:dashboard_api\*/}) do
      DashboardApiController.action(:index).call(@env)
    end
  ensure
    comment_context.components = @default_components
  end
end
