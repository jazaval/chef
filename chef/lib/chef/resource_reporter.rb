#
# Author:: Daniel DeLeo (<dan@opscode.com>)
# Author:: Prajakta Purohit (prajakta@opscode.com>)
#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'uri'

class Chef
  class ResourceReporter

    class ResourceReport < Struct.new(:new_resource,
                                      :current_resource,
                                      :action,
                                      :exception,
                                      :elapsed_time)

      def self.new_with_current_state(new_resource, action, current_resource)
        report = new
        report.new_resource = new_resource
        report.action = action
        report.current_resource = current_resource
        report
      end

      def self.new_for_exception(new_resource, action)
        report = new
        report.new_resource = new_resource
        report.action = action
        report
      end

      def for_json
        as_hash = {}
        as_hash["type"]   = new_resource.class.dsl_name
        as_hash["name"]   = new_resource.name
        as_hash["id"]     = new_resource.identity
        as_hash["after"]  = new_resource.state
        as_hash["before"] = current_resource.state if current_resource
        as_hash["elapsed_time"] = elapsed_time
        as_hash["action"] = action.to_s
        if success?
        else
          #as_hash["result"] = "failed"
        end
        as_hash

      end

      def success?
        !self.exception
      end
    end

    attr_reader :updated_resources
    attr_reader :status
    attr_reader :exception
    attr_reader :run_id

    def initialize(rest_client)
      @updated_resources = []
      @pending_update  = nil
      @status = "success"
      @exception = nil
      @run_id = nil
      @rest_client = rest_client
      @node = nil
    end

    def node_load_completed(node, expanded_run_list_with_versions, config)
      @node = node
      resource_history_url = "nodes/#{@node.name}/audit"
      server_response = @rest_client.post_rest(resource_history_url, {:action => :begin})
      run_uri = URI.parse(server_response["uri"])
      @run_id = ::File.basename(run_uri.path)
    end

    def resource_action_start(resource, action, notification_type=nil, notifier=nil)
      @start_time = Time.new
    end

    def resource_current_state_loaded(new_resource, action, current_resource)
      @pending_update = ResourceReport.new_with_current_state(new_resource, action, current_resource)
    end

    def resource_up_to_date(new_resource, action)
      @pending_update = nil
      @start_time =nil
    end

    def resource_updated(new_resource, action)
      resource_completed
    end

    def resource_failed(new_resource, action, exception)
      @pending_update ||= ResourceReport.new_for_exception(new_resource, action)
      @pending_update.exception = exception
      resource_completed
    end

    def run_completed
      resource_history_url = "nodes/#{@node.name}/audit/#{run_id}"
      run_data = report
      run_data["action"] = "end"
      @rest_client.post_rest(resource_history_url, run_data)
    end

    def run_failed(exception)
      @exception = exception
      @status = "failed"
    end

    def report
      run_data = {}
      run_data["resources"] = updated_resources.map do |resource_record|
        resource_record.for_json
      end
      run_data["status"] = status
      run_data
    end

    private

    def resource_completed
      @pending_update.elapsed_time = Time.new - @start_time
      @updated_resources << @pending_update
      @pending_update = nil
    end

  end
end
