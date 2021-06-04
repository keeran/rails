# frozen_string_literal: true

require "isolation/abstract_unit"
require "rack/test"

module ApplicationTests
  class QueryLogTagsTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::Isolation
    include Rack::Test::Methods

    ActiveRecord::QueryLogTags = ActiveRecord::ConnectionAdapters::AbstractAdapter::QueryLogTagsContext

    def setup
      build_app
      app_file "app/models/user.rb", <<-MODEL
        class User < ActiveRecord::Base
        end
      MODEL

      app_file "app/controllers/users_controller.rb", <<-CONTROLLER
        class UsersController < ApplicationController
          def index
            @users = User.all
          end
        end
      CONTROLLER

      app_file "app/jobs/user_job.rb", <<-JOB
        class UserJob < ActiveJob::Base
          def perform
            users = User.all
          end
        end
      JOB
    end

    def teardown
      teardown_app
    end

    def app
      @app ||= Rails.application
    end

    test "does not modify the query execution path by default" do
      boot_app

      assert_equal ActiveRecord::Base.connection.method(:execute).owner, ActiveRecord::ConnectionAdapters::SQLite3::DatabaseStatements
    end

    test "prepends the query execution path when enabled" do
      add_to_config "config.active_record.query_log_tags_enabled = true"

      boot_app

      assert_equal ActiveRecord::Base.connection.method(:execute).owner, ActiveRecord::ConnectionAdapters::QueryLogTags::ExecutionMethods
    end

    test "controller and job tags are defined by default" do
      add_to_config "config.active_record.query_log_tags_enabled = true"

      boot_app

      assert_equal ActiveRecord::QueryLogTags.components, [:application, :controller, :action, :job]
    end

    test "controller actions have tagging filters enabled by default" do
      add_to_config "config.active_record.query_log_tags_enabled = true"

      boot_app

      controller = UsersController.new
      filters = controller._process_action_callbacks.map { |cb| cb.filter }

      assert_includes filters, :record_query_log_tags
    end

    test "controller actions tagging filters can be disabled" do
      add_to_config "config.active_record.query_log_tags_enabled = true"
      add_to_config "config.action_controller.query_log_tags_action_filter_enabled = false"

      boot_app

      controller = UsersController.new
      filters = controller._process_action_callbacks.map { |cb| cb.filter }

      assert_not_includes filters, :record_query_log_tags
    end

    test "job perform method has tagging filters enabled by default" do
      add_to_config "config.active_record.query_log_tags_enabled = true"

      boot_app

      job = UserJob.new
      proc_locations = job._perform_callbacks.map { |cb| cb.filter.source_location.first.delete_prefix(framework_path) }

      assert_includes proc_locations, "/activerecord/lib/active_record/railties/query_log_tags.rb"
    end

    test "job perform method tagging filters can be disabled" do
      add_to_config "config.active_record.query_log_tags_enabled = true"
      add_to_config "config.active_job.query_log_tags_action_filter_enabled = false"

      boot_app

      job = UserJob.new
      proc_locations = job._perform_callbacks.map { |cb| cb.filter.source_location.first.delete_prefix(framework_path) }

      assert_not_includes proc_locations, "/activerecord/lib/active_record/railties/query_log_tags.rb"
    end

    test "query cache is cleared between requests" do
      add_to_config "config.active_record.query_log_tags_enabled = true"
      ActiveRecord::QueryLogTags.cache_query_log_tags = true

      app_file "config/routes.rb", <<-RUBY
        Rails.application.routes.draw do
          get "/", to: "users#index"
        end
      RUBY

      boot_app

      assert_not_nil ActiveRecord::QueryLogTags.comment
      assert_not_nil ActiveRecord::QueryLogTags.cached_comment

      get "/"

      assert_nil ActiveRecord::QueryLogTags.cached_comment
    end

    test "query cache is cleared between job executions" do
      add_to_config "config.active_record.query_log_tags_enabled = true"
      ActiveRecord::QueryLogTags.cache_query_log_tags = true

      boot_app

      assert_not_nil ActiveRecord::QueryLogTags.comment
      assert_not_nil ActiveRecord::QueryLogTags.cached_comment

      UserJob.new.perform_now

      assert_nil ActiveRecord::QueryLogTags.cached_comment
    end

    private
      def boot_app(env = "production")
        ENV["RAILS_ENV"] = env

        require "#{app_path}/config/environment"
      ensure
        ENV.delete "RAILS_ENV"
      end
  end
end