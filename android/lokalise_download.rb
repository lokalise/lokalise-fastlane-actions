module Fastlane
  module Actions
    class LokaliseAction < Action
      def self.run(params)
        require 'net/http'
        require 'json'
        require 'zip'
        require 'rubygems'

        token = params[:api_token]
        project_identifier = params[:project_identifier]
        destination = params[:destination]

        request_data = {
            format: "xml",
            original_filenames: false,
            bundle_structure: "values-%LANG_ISO%/strings.%FORMAT%",
            ota_plugin_bundle: 0,
            export_empty: "base",
            include_comments: false,
            replace_breaks: true
        }

        languages = params[:languages]
        if languages.kind_of? Array
          request_data["langs"] = languages.to_json
        end

        tags = params[:tags]
        if tags.kind_of? Array
          request_data["include_tags"] = tags.to_json
        end

        uri = URI("https://api.lokalise.com/api2/projects/#{project_identifier}/files/download")
        request = Net::HTTP::Post.new(uri)
        request["content-type"] = 'application/json'
        request["x-api-token"] = token
        request.body = request_data.to_json

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.request(request)

        jsonResponse = JSON.parse(response.body)
        UI.error "Bad response 🉐\n#{response.body}" unless jsonResponse.kind_of? Hash
        if jsonResponse["bundle_url"].kind_of?(String)  then
          UI.message "Downloading localizations archive 📦"
          FileUtils.mkdir_p("lokalisetmp")
          fileURL = jsonResponse["bundle_url"]
          uri = URI(fileURL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          zipRequest = Net::HTTP::Get.new(uri)
          response = http.request(zipRequest)
          if response.content_type == "application/zip" or response.content_type == "application/octet-stream" then
            FileUtils.mkdir_p("lokalisetmp")
            open("lokalisetmp/a.zip", "wb") { |file|
              file.write(response.body)
            }
            unzip_file("lokalisetmp/a.zip", destination)
            FileUtils.remove_dir("lokalisetmp")
            UI.success "Localizations extracted to #{destination} 📗 📕 📘"
          else
            UI.error "Response did not include ZIP"
          end
        elsif jsonResponse["error"]["code"].kind_of?(Integer)
          code = jsonResponse["error"]["code"]
          message = jsonResponse["error"]["message"]
          UI.error "Response error code #{code} (#{message}) 📟"
        else
          UI.error "Bad response 🉐\n#{jsonResponse}"
        end
      end


      def self.unzip_file(file, destination)
        Zip::File.open(file) { |zip_file|
          UI.message "Unarchiving localizations to destination 📚"
          zip_file.each { |f|
            f_path= File.join(destination, f.name)
            FileUtils.mkdir_p(File.dirname(f_path))
            FileUtils.rm(f_path) if File.file? f_path
            zip_file.extract(f, f_path)
          }
        }
      end


      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Download Android localization from Lokalise"
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
            FastlaneCore::ConfigItem.new(key: :languages,
                                         description: "Languages to download",
                                         optional: true,
                                         is_string: false,
                                         verify_block: proc do |value|
                                           UI.user_error! "Language codes should be passed as array" unless value.kind_of? Array
                                         end),
            FastlaneCore::ConfigItem.new(key: :tags,
                                         description: "Include only the keys tagged with a given set of tags",
                                         optional: true,
                                         is_string: false,
                                         verify_block: proc do |value|
                                           UI.user_error! "Tags should be passed as array" unless value.kind_of? Array
                                         end),

        ]
      end

      def self.authors
        "simonkarmy"
      end

      def self.is_supported?(platform)
        [:android].include? platform
      end
    end
  end
end
