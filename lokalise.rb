module Fastlane
  module Actions
    class LokaliseAction < Action
      def self.run(params)
        require 'net/http'

        token = params[:api_token]
        project_identifier = params[:project_identifier]
        destination = params[:destination]
        clean_destination = params[:clean_destination]
        include_comments = params[:include_comments]
        original_filenames = params[:use_original]
        replace_breaks = params[:replace_breaks]
        escape_percent = params[:escape_percent]
        max_retries = params[:max_retries]
        retry_delay = params[:retry_delay]

        body = {
          format: "ios_sdk",
          original_filenames: original_filenames,
          bundle_filename: "Localization.zip",
          bundle_structure: "%LANG_ISO%.lproj/Localizable.%FORMAT%",
          export_empty_as: "base",
          export_sort: "first_added",
          include_comments: include_comments,
          replace_breaks: replace_breaks,
          escape_percent: escape_percent
        }

        filter_langs = params[:languages]
        if filter_langs.kind_of? Array then
          body["filter_langs"] = filter_langs
        end

        tags = params[:tags]
        if tags.kind_of? Array then
          body["include_tags"] = tags
        end

        uri = URI("https://api.lokalise.com/api2/projects/#{project_identifier}/files/async-download")
        response = perform_request(method: "post", uri: uri, token: token, body: body)

        jsonResponse = JSON.parse(response.body)
        UI.error "Bad response 🉐\n#{response.body}" unless jsonResponse.kind_of? Hash
        if response.code == "200" && jsonResponse["process_id"].kind_of?(String) then
          processId = jsonResponse["process_id"]
          UI.message "Async download started (process_id: #{processId}) ⏳"
          FileUtils.mkdir_p("lokalisetmp")
          
          status = nil
          download_url = nil

          max_retries.times do |attempt|
            sleep(retry_delay) if attempt > 0
            poll_uri = URI("https://api.lokalise.com/api2/projects/#{project_identifier}/processes/#{processId}")
            poll_response = perform_request(method: "get", uri: poll_uri, token: token)
            poll_json = JSON.parse(poll_response.body)

            process = poll_json["process"]
            status = process["status"]
            message = process["message"]

            UI.message "Status: #{status} (attempt #{attempt + 1}/#{max_retries})"

            case status
            when "finished"
              download_url = process["details"] && process["details"]["download_url"]
              break
            when "failed", "cancelled"
              UI.error "Process #{status}: #{message}"
              return
            else
              UI.message "Process status: #{status} (attempt #{attempt + 1}/#{max_retries})"
            end
          end

          if status != "finished" || download_url.nil?
            UI.error "Download did not finish in time or missing URL"
            return
          end

          download_and_unzip(download_url, destination, clean_destination)
        elsif jsonResponse["error"].kind_of? Hash
          code = jsonResponse["error"]["code"]
          message = jsonResponse["error"]["message"]
          UI.error "Response error code #{code} (#{message}) 📟"
        else
          UI.error "Bad response 🉐\n#{jsonResponse}"
        end
      end

      def self.download_and_unzip(file_url, destination, clean_destination)
        require 'open-uri'
        require 'zip'

        UI.message "Downloading ZIP from #{file_url}"
        FileUtils.mkdir_p("lokalisetmp")
        zip_path = "lokalisetmp/a.zip"

        URI.open(file_url) do |remote|
          File.write(zip_path, remote.read)
        end

        unzip_file(zip_path, destination, clean_destination)
        FileUtils.remove_dir("lokalisetmp")
        UI.success "Localizations extracted to #{destination}"
      end

      def self.unzip_file(file, destination, clean_destination)
        require 'zip'
        require 'rubygems'
        Zip::File.open(file) { |zip_file|
          if clean_destination then
            UI.message "Cleaning destination folder ♻️"
            FileUtils.remove_dir(destination)
            FileUtils.mkdir_p(destination)
          end
          UI.message "Unarchiving localizations to destination 📚"
           zip_file.each { |f|
             f_path= File.join(destination, f.name)
             FileUtils.mkdir_p(File.dirname(f_path))
             FileUtils.rm(f_path) if File.file? f_path
             zip_file.extract(f, f_path)
           }
        }
      end

      def self.perform_request(method:, uri:, token:, body: nil)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = case method.to_s.downcase
                  when "post"
                    Net::HTTP::Post.new(uri)
                  when "get"
                    Net::HTTP::Get.new(uri)
                  else
                    UI.user_error!("Unsupported HTTP method: #{method}")
                  end

        request["x-api-token"] = token
        request["Content-Type"] = "application/json" if body
        request.body = body.to_json if body

        http.request(request)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Download Lokalise localization"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: "LOKALISE_API_TOKEN",
                                       description: "API Token for Lokalise",
                                       verify_block: proc do |value|
                                          UI.user_error! "No API token for Lokalise given, pass using `api_token: 'token'`" unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :project_identifier,
                                       env_name: "LOKALISE_PROJECT_ID",
                                       description: "Lokalise Project ID",
                                       verify_block: proc do |value|
                                          UI.user_error! "No Project Identifier for Lokalise given, pass using `project_identifier: 'identifier'`" unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :destination,
                                       description: "Localization destination",
                                       verify_block: proc do |value|
                                          UI.user_error! "Things are pretty bad" unless (value and not value.empty?)
                                          UI.user_error! "Directory you passed is in your imagination" unless File.directory?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :clean_destination,
                                       description: "Clean destination folder",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Clean destination should be true or false" unless [true, false].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :languages,
                                       description: "Languages to download",
                                       optional: true,
                                       is_string: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Language codes should be passed as array" unless value.kind_of? Array
                                       end),
          FastlaneCore::ConfigItem.new(key: :include_comments,
                                       description: "Include comments in exported files",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Include comments should be true or false" unless [true, false].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :use_original,
                                       description: "Use original filenames/formats (bundle_structure parameter is ignored then)",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Use original should be true of false." unless [true, false].include?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :tags,
                                       description: "Include only the keys tagged with a given set of tags",
                                       optional: true,
                                       is_string: false,
                                       verify_block: proc do |value|
                                          UI.user_error! "Tags should be passed as array" unless value.kind_of? Array
                                       end),
          FastlaneCore::ConfigItem.new(key: :replace_breaks,
                                       description: "Replace line breaks with \\n in Lokalise export",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                          UI.user_error!("replace_breaks must be true or false") unless [true, false].include?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :escape_percent,
                                       description: "Escape % characters in Lokalise export",
                                       optional: true,
                                       is_string: false,
                                       default_value: true,
                                       verify_block: proc do |value|
                                          UI.user_error!("escape_percent must be true or false") unless [true, false].include?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :max_retries,
                                       description: "Maximum number of polling attempts for Lokalise process",
                                       optional: true,
                                       is_string: false,
                                       default_value: 60,
                                       verify_block: proc do |value|
                                          UI.user_error!("max_retries must be a positive Integer") unless value.is_a?(Integer) && value > 0
                                       end),
          FastlaneCore::ConfigItem.new(key: :retry_delay,
                                       description: "Delay in seconds between polling attempts",
                                       optional: true,
                                       is_string: false,
                                       default_value: 5,
                                       verify_block: proc do |value|
                                          UI.user_error!("retry_delay must be a positive Integer") unless value.is_a?(Integer) && value > 0
                                       end)

        ]
      end

      def self.authors
        "Fedya-L"
      end

      def self.is_supported?(platform)
        [:ios, :mac].include? platform 
      end
    end
  end
end
