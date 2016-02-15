module Fastlane
  module Actions
    class LokaliseAction < Action
      def self.run(params)
        require 'net/http'

        token = params[:api_token]
        project_identifier = params[:project_identifier]
        destination = params[:destination]
        clean_destination = params[:clean_destination]

        request_data = {
          api_token: token,
          id: project_identifier,
          type: "strings",
          use_original: 0,
          bundle_filename: "Localization.zip",
          bundle_structure: "%LANG_ISO%.lproj/Localizable.%FORMAT%",
          ota_plugin_bundle: 0,
          export_empty: "base"
        }

        languages = params[:languages]
        if languages.kind_of? Array then
          request_data["langs"] = languages.to_json
        end

        uri = URI("https://lokali.se/api/project/export")
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(request_data)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.request(request)


        jsonResponse = JSON.parse(response.body)
        raise "Bad response 🉐\n#{response.body}".red unless jsonResponse.kind_of? Hash
        if jsonResponse["response"]["status"] == "success" && jsonResponse["bundle"]["file"].kind_of?(String)  then
          Helper.log.info "Downloading localizations archive 📦".green
          FileUtils.mkdir_p("lokalisetmp")
          filePath = jsonResponse["bundle"]["file"]
          uri = URI("https://lokali.se/#{filePath}")
          zipRequest = Net::HTTP::Get.new(uri)
          response = http.request(zipRequest)
          if response.content_type == "application/zip" then
            FileUtils.mkdir_p("lokalisetmp")
            open("lokalisetmp/a.zip", "wb") { |file| 
              file.write(response.body)
            }
            unzip_file("lokalisetmp/a.zip", destination, clean_destination)
            FileUtils.remove_dir("lokalisetmp")
            Helper.log.info "Localizations extracted to #{destination} 📗 📕 📘".green
          else
            raise "Response did not include ZIP".red
          end
        elsif jsonResponse["response"]["status"] == "error"
          code = jsonResponse["response"]["code"]
          message = jsonResponse["response"]["message"]
          raise "Response error code #{code} (#{message}) 📟".red
        else
          raise "Bad response 🉐\n#{jsonResponse}".red
        end
      end


      def self.unzip_file(file, destination, clean_destination)
        require 'zip'
        require 'rubygems'
        Zip::File.open(file) { |zip_file|
          if clean_destination then
            Helper.log.info "Cleaning destination folder ♻️".green
            FileUtils.remove_dir(destination)
            FileUtils.mkdir_p(destination)
          end
          Helper.log.info "Unarchiving localizations to destination 📚".green
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
        "Download Lokalise localization"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: "LOKALISE_API_TOKEN",
                                       description: "API Token for Lokalise",
                                       verify_block: proc do |value|
                                          raise "No API token for Lokalise given, pass using `api_token: 'token'`".red unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :project_identifier,
                                       env_name: "LOKALISE_PROJECT_ID",
                                       description: "Create a development certificate instead of a distribution one",
                                       verify_block: proc do |value|
                                          raise "No Project Identifier for Lokalise given, pass using `project_identifier: 'identifier'`".red unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :destination,
                                       description: "Localization destination",
                                       verify_block: proc do |value|
                                          raise "Things are pretty bad".red unless (value and not value.empty?)
                                          raise "Directory you passed is in your imagination".red unless File.directory?(value)
                                       end),
          FastlaneCore::ConfigItem.new(key: :clean_destination,
                                       description: "Clean destination folder",
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                          raise "Clean destination should be true or false".red unless [true, false].include? value
                                       end),
          FastlaneCore::ConfigItem.new(key: :languages,
                                       description: "Languages to download",
                                       optional: true,
                                       is_string: false,
                                       verify_block: proc do |value|
                                          raise "Language codes should be passed as array".red unless value.kind_of? Array
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