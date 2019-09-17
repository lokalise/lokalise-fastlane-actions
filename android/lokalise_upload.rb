module Fastlane
  module Actions
    class LokaliseUploadAction < Action
      def self.run(params)
        require 'net/http'
        require 'json'
        require 'base64'

        token = params[:api_token]
        project_identifier = params[:project_identifier]
        languages = params[:languages]

        for lang_code in languages do
          file_path = (lang_code == "en" ? "./app/src/main/res/values/strings.xml" : "./app/src/main/res/values-#{lang_code}/strings.xml")
          self.upload_lang(token, project_identifier, lang_code, file_path)
        end
      end

      def self.upload_lang(token, project_id, lang_code, lang_file_path)

        file_data = File.open(lang_file_path, "r").read
        file_data_64 = Base64.encode64(file_data).delete("\n")

        request_data = {
            filename: "strings.xml",
            data: file_data_64 ,
            lang_iso: lang_code,
            convert_placeholders: true ,
            slashn_to_linebreak: true
        }

        uri = URI("https://api.lokalise.com/api2/projects/#{project_id}/files/upload")
        request = Net::HTTP::Post.new(uri)
        request["content-type"] = 'application/json'
        request["x-api-token"] = token
        request.body = request_data.to_json

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.request(request)

        jsonResponse = JSON.parse(response.body)
        UI.error "Bad response 🉐\n#{response.body}" unless jsonResponse.kind_of? Hash
        if jsonResponse["project_id"].kind_of?(String)  then
          UI.message "Uploaded localization file for #{lang_code} successfully #{jsonResponse["result"]}"
        elsif jsonResponse["error"]["code"].kind_of?(Integer)
          code = jsonResponse["error"]["code"]
          message = jsonResponse["error"]["message"]
          UI.error "Response error code #{code} (#{message}) 📟"
        else
          UI.error "Bad response 🉐\n#{jsonResponse}"
        end
      end


      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Upload Android strings.xml to Lokalise"
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
            FastlaneCore::ConfigItem.new(key: :languages,
                                         description: "Languages to download",
                                         optional: true,
                                         is_string: false,
                                         verify_block: proc do |value|
                                           UI.user_error! "Language codes should be passed as array" unless value.kind_of? Array
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
