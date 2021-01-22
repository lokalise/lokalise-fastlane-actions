require 'net/http'

module Fastlane
  module Actions
    class AddKeysToLokaliseAction < Action
      class << self
        def run(params)
          token = params[:api_token]
          project_id = params[:project_identifier]
          raw_keys = params[:keys]
          platforms = params[:platforms]

          keys = {keys: []}

          raw_keys.each do |key|
            keys[:keys] << {
              key_name: key,
              platforms: platforms.map(&:downcase)
            }
          end

          uri = URI("https://api.lokalise.com/api2/projects/#{project_id}/keys")
          request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
          request.body = keys.to_json
          request.add_field("x-api-token", token)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          response = http.request(request)
          jsonResponse = JSON.parse(response.body)

          raise "Bad response 🉐\n#{response.body}".red unless jsonResponse.kind_of? Hash
          if response.kind_of? Net::HTTPSuccess
            inserted = jsonResponse["keys"].count
            UI.success "Keys uploaded. #{inserted} inserted 🚀"
          elsif jsonResponse["response"]["status"] == "error"
            code = jsonResponse["response"]["code"]
            message = jsonResponse["response"]["message"]
            raise "Response error code #{code} (#{message}) 📟".red
          else
            raise "Bad response 🉐\n#{jsonResponse}".red
          end
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Add keys to lokalise"
        end

        def available_options
          [
            FastlaneCore::ConfigItem.new(key: :api_token,
                                        env_name: "LOKALISE_API_TOKEN",
                                        description: "API Token for Lokalise",
                                        is_string: true,
                                        verify_block: proc do |value|
                                            raise "No API token for Lokalise given, pass using `api_token: 'token'`".red unless (value and not value.empty?)
                                        end),
            FastlaneCore::ConfigItem.new(key: :project_identifier,
                                        env_name: "LOKALISE_PROJECT_ID",
                                        description: "Lokalise Project Identifier",
                                        is_string: true,
                                        verify_block: proc do |value|
                                            raise "No Project Identifier for Lokalise given, pass using `project_identifier: 'identifier'`".red unless (value and not value.empty?)
                                        end),
            FastlaneCore::ConfigItem.new(key: :platforms,
                                        description: "Platforms array. Supported values: ios, web, android, other",
                                        optional: true,
                                        is_string: false,
                                        default_value: %w[ios],
                                        verify_block: proc do |value|
                                            raise "Keys must be passed as array of strings".red unless (value.is_a? Array and !value.empty?)
                                            value.each.with_index do |key, index|
                                              raise "Key at index #{index} must be string".red unless key.is_a? String
                                              raise "Key at index #{index} must be ios, android, web, or other" unless %w[ios android other web].include?(key.downcase)
                                            end
                                        end),
            FastlaneCore::ConfigItem.new(key: :keys,
                                        description: "Keys to add",
                                        optional: false,
                                        is_string: false,
                                        verify_block: proc do |value|
                                            raise "Keys must be passed as array of strings".red unless (value.kind_of? Array and !value.empty?)
                                            value.each_with_index do |key, index|
                                              raise "Key at index #{index} must be string".red unless key.kind_of? String
                                              raise "Key at index #{index} can't be empty".red if key.empty?
                                            end
                                        end)
          ]
        end

        def authors
          "Fedya-L"
        end

        def is_supported?(platform)
          [:ios, :mac].include? platform
        end
      end
    end
  end
end
