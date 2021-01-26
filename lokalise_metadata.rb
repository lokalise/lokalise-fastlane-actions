require 'net/http'

module Fastlane
  module Actions
    class LokaliseMetadataAction < Action
      class << self
        def run(params)
          @params = params
          action = params[:action]

          case action
          when "update_itunes"
            key_file = metadata_key_file_itunes
            metadata = get_metadata_from_lokalise_itunes
            run_deliver_action metadata
          when "update_googleplay"
            release_number = params[:release_number]
            UI.user_error! "Release number is required when using `update_googleplay` action (should be an integer and greater that 0)" unless (release_number and release_number.is_a?(Integer) and release_number > 0)
            key_file = metadata_key_file_googleplay
            metadata = get_metadata_from_lokalise_googleplay
            save_metadata_to_files metadata, release_number
            run_supply_action params[:validate_only]
          when "update_lokalise_itunes"
            metadata = get_metadata_itunes_connect
            add_languages = params[:add_languages]
            override_translation = params[:override_translation]
            create_languages(metadata.keys, true) if add_languages

            if override_translation
              upload_metadata_itunes(metadata) unless metadata.empty?
            else
              lokalise_metadata = get_metadata_from_lokalise_itunes
              filtered_metadata = filter_metadata(metadata, lokalise_metadata)
              upload_metadata_itunes(filtered_metadata) unless filtered_metadata.empty?
            end
          when "update_lokalise_googleplay"
            metadata = get_metadata_google_play
            add_languages = params[:add_languages]
            override_translation = params[:override_translation]

            create_languages(metadata.keys, false) if add_languages

            if override_translation
              upload_metadata_google_play(metadata) unless metadata.empty?
            else
              lokalise_metadata = get_metadata_from_lokalise_googleplay
              filtered_metadata = filter_metadata(metadata, lokalise_metadata)
              upload_metadata_google_play(filtered_metadata) unless filtered_metadata.empty?
            end
          end
        end

        def create_languages(languages, for_itunes)
          data = {
            languages: languages.map { |language| {lang_iso: fix_language_name(language, for_itunes, true)} }
          }
          make_request "languages", data
        end

        def filter_metadata(metadata, other_metadata)
          filtered_metadata = {}
          metadata.each do |language, translations|
            other_translations = other_metadata[language]
            filtered_translations = {}

            if !other_translations.nil? && !other_translations.empty?
              translations.each do |key, value|
                other_value = other_translations[key]
                filtered_translations[key] = value unless !other_value.nil? && !other_value.empty?
              end
            else
              filtered_translations = translations
            end

            filtered_metadata[language] = filtered_translations unless filtered_translations.empty?
          end

          filtered_metadata
        end

        def run_deliver_action(metadata)
          config = FastlaneCore::Configuration.create(Actions::DeliverAction.available_options, {})
          config.load_configuration_file("Deliverfile")
          config[:metadata_path] = "./fastlane/no_metadata"
          config[:screenshots_path] = "./fastlane/no_screenshot"
          config[:skip_screenshots] = true
          config[:run_precheck_before_submit] = false
          config[:skip_binary_upload] = true
          config[:skip_app_version_update] = true
          config[:force] = true

          metadata_key_file_itunes.each do |key, parameter|
            final_translations = {}

            metadata.each do |lang, translations|
              if !translations.empty?
                translation = translations[key]
                final_translations[lang] = translation if !translation.nil? && !translation.empty?
              end
            end

            config[parameter.to_sym] = final_translations
          end

          Actions::DeliverAction.run config
        end

        def run_supply_action(validate_only)
          config = FastlaneCore::Configuration.create(Actions::SupplyAction.available_options, {})
          config[:skip_upload_apk] = true
          config[:skip_upload_aab] = true
          config[:skip_upload_screenshots] = true
          config[:skip_upload_images] = true
          config[:validate_only] = validate_only

          Actions::SupplyAction.run(config)
        end

        def save_metadata_to_files(metadata, release_number)
          translations = {}

          metadata_key_file_googleplay.each do |key, parameter|
            final_translations = {}

            metadata.each do |lang, translations|
              if !translations.empty?
                translation = translations[key]
                final_translations[lang] = translation if !translation.nil? && !translation.empty?
              end
            end

            translations[parameter.to_sym] = final_translations
          end

          FileUtils.rm_rf Dir['fastlane/metadata/android/*']

          translations.each do |key, parameter|
            parameter.each do |lang, text|
              path = "fastlane/metadata/android/#{lang}/#{key}.txt"
              if "#{key}" == "changelogs"
                path = "fastlane/metadata/android/#{lang}/changelogs/#{release_number}.txt"
              end
              dirname = File.dirname(path)
              unless File.directory?(dirname)
                FileUtils.mkdir_p dirname
              end
              File.write path, text
            end
          end

        end

        def make_request(path, data, resp_type = :post, allow_fail = false)
          uri = URI("https://api.lokalise.com/api2/projects/#{@params[:project_identifier]}/#{path}")
          request = nil

          if resp_type == :post
            request = Net::HTTP::Post.new uri, 'Content-Type' => 'application/json', 'Accept' => 'application/json'
            request.body = data.to_json
          elsif resp_type == :put
            request = Net::HTTP::Put.new uri, 'Content-Type' => 'application/json', 'Accept' => 'application/json'
            request.body = data.to_json
          else
            request = Net::HTTP::Get.new uri, 'Accept' => 'application/json'
          end

          request.add_field "x-api-token", @params[:api_token]
          http = Net::HTTP.new uri.host, uri.port
          http.use_ssl = true
          response = http.request request

          jsonResponse = JSON.parse(response.body)

          unless allow_fail
            raise "Bad response 🉐\n#{response.body}" unless jsonResponse.kind_of? Hash
            if response.kind_of? Net::HTTPSuccess
              UI.success "Response #{jsonResponse} 🚀"
            elsif jsonResponse["error"]
              code = jsonResponse["error"]["code"]
              message = jsonResponse["error"]["message"]
              raise "Response error code #{code} (#{message}) 📟"
            else
              raise "Bad response 🉐\n#{jsonResponse}"
            end
          end
          jsonResponse
        end

        def upload_metadata(metadata_keys, for_itunes, metadata)
          keys_to_add = { keys: [] }

          metadata_keys.each do |key, _value|
            key = key_object_without_trans_from_metadata key, metadata, for_itunes
            keys_to_add[:keys] << key if key
          end

          make_request "keys", keys_to_add, :post, true

          names = keys_to_add[:keys].map {|k| k[:key_name] }
          found_keys = make_request "keys?filter_keys=#{names.join(',')}", nil, :get
          ids_names = found_keys['keys'].map {|k| {k['key_id'] => k['key_name']['other']} }

          keys_to_update = { keys: [] }
          ids_names.each do |element|
            element.each do |id, name|
              key = make_key_object_from_metadata id, name, metadata, for_itunes
              keys_to_update[:keys] << key if key
            end
          end
          make_request "keys", keys_to_update, :put
        end

        def make_key_object_from_metadata(key_id, key_name, metadata, for_itunes)
          key_data = {
            "key_id": key_id,
            "platforms": ['other'],
            "translations": []
          }

          metadata.each do |iso_code, data|
            translation = data[key_name]

            unless translation.nil? || translation.empty?
              key_data[:translations].push({
                "language_iso": fix_language_name(iso_code, for_itunes, true),
                "translation": translation
              })
            end
          end

          key_data[:translations].empty? ? nil : key_data
        end

        def key_object_without_trans_from_metadata(key, metadata, for_itunes)
          key_data = {
            key_name: key,
            platforms: ['other']
          }

          key ? key_data : nil
        end

        def upload_metadata_itunes(metadata)
          upload_metadata metadata_key_file_itunes, true, metadata
        end

        def upload_metadata_google_play(metadata)
          upload_metadata metadata_key_file_googleplay, false, metadata
        end

        def get_metadata_google_play
          get_metadata google_play_languages, "fastlane/metadata/android/", false
        end

        def get_metadata_itunes_connect
          get_metadata itunes_connect_languages, "fastlane/metadata/", true
        end

        def get_metadata(available_languages, folder, for_itunes)
          complete_metadata = {}

          available_languages.each do |iso_code|
            language_directory = "#{folder}#{iso_code}"
            if Dir.exist? language_directory
              language_metadata = {}
              if for_itunes
                metadata_key_file_itunes.each do |key, file|
                  populate_hash_key_from_file language_metadata, key, language_directory + "/#{file}.txt"
                end
              else
                metadata_key_file_googleplay.each do |key, file|
                  if file == "changelogs"
                    changelog_directory = "#{folder}#{iso_code}/changelogs"
                    files = Dir.entries("#{changelog_directory}")
                    collectedFiles = files.collect { |s| s.partition(".").first.to_i }
                    sortedFiles = collectedFiles.sort
                    populate_hash_key_from_file language_metadata, key, language_directory + "/changelogs/#{sortedFiles.last}.txt"
                  else
                    populate_hash_key_from_file language_metadata, key, language_directory + "/#{file}.txt"
                  end
                end
              end
              complete_metadata[iso_code] = language_metadata
            end
          end

          complete_metadata
        end

        def get_metadata_from_lokalise(valid_keys, for_itunes)
          response = make_request "keys?include_translations=1&filter_platforms=other&filter_keys=#{valid_keys.join(',')}", nil, :get
          valid_languages = for_itunes ? itunes_connect_languages_in_lokalise : google_play_languages_in_lokalise
          metadata = {}

          response["keys"].each do |raw_key|
            raw_key['translations'].each do |raw_translation|
              lang = raw_translation['language_iso']
              if valid_languages.include? lang
                key = raw_key['key_name']['other']
                translation = raw_translation['translation']

                if valid_keys.include?(key) && !translation.nil? && !translation.empty?
                  fixed_lang_name = fix_language_name lang, for_itunes
                  metadata[fixed_lang_name] = {} unless metadata.has_key?(fixed_lang_name)
                  metadata[fixed_lang_name] = metadata[fixed_lang_name].merge({key => translation})
                end
              end
            end
          end
          metadata
        end

        def get_metadata_from_lokalise_itunes
          valid_keys = metadata_keys_itunes
          get_metadata_from_lokalise valid_keys, true
        end

        def get_metadata_from_lokalise_googleplay
          get_metadata_from_lokalise metadata_keys_googleplay, false
        end

        def populate_hash_key_from_file(hash, key, filepath)
          begin
            text = File.read filepath
            text.chomp!
            hash[key] = text unless text.empty?
          rescue => exception
            raise exception
          end
        end

        def metadata_keys_itunes
          metadata_key_file_itunes.keys
        end

        def metadata_keys_googleplay
          metadata_key_file_googleplay.keys
        end

        def metadata_key_file_itunes
          {
            "appstore.app.name" => "name",
            "appstore.app.description" => "description",
            "appstore.app.keywords" => "keywords",
            "appstore.app.promotional_text" => "promotional_text",
            "appstore.app.release_notes" => "release_notes",
            "appstore.app.subtitle" => "subtitle",
          }
        end

        def metadata_key_file_googleplay
          {
            "googleplay.app.title" => "title",
            "googleplay.app.full_description" => "full_description",
            "googleplay.app.short_description" => "short_description",
            "googleplay.app.changelogs" => "changelogs",
          }
        end

        def itunes_connect_languages_in_lokalise
          itunes_connect_languages.map { |lang|
            fix_language_name lang, true, true
          }
        end

        def google_play_languages_in_lokalise
          google_play_languages.map do |lang|
            fix_language_name lang, false, true
          end
        end

        def itunes_connect_languages
          [
            "en-US",
            "zh-Hans",
            "zh-Hant",
            "da",
            "nl-NL",
            "en-AU",
            "en-CA",
            "en-GB",
            "fi",
            "fr-FR",
            "fr-CA",
            "de-DE",
            "el",
            "id",
            "it",
            "ja",
            "ko",
            "ms",
            "no",
            "pt-BR",
            "pt-PT",
            "ru",
            "es-MX",
            "es-ES",
            "sv",
            "th",
            "tr",
            "vi"
          ]
        end

        def google_play_languages
          [
            'af',
            'am',
            'ar',
            'hy',
            'az-AZ',
            'eu-ES',
            'be',
            'bn-BD',
            'bg',
            'my',
            'ca',
            'zh-CN',
            'zh-TW',
            'zh-HK',
            'hr',
            'cs',
            'da',
            'nl-NL',
            'en-AU',
            'en-CA',
            'en-IN',
            'en-SG',
            'en-ZA',
            'en-GB',
            'en-US',
            'et-EE',
            'fil',
            'fi',
            'fr-CA',
            'fr-FR',
            'gl-ES',
            'ka-GE',
            'de-DE',
            'el-GR',
            'he',
            'hi-IN',
            'hu',
            'is-IS',
            'id',
            'it-IT',
            'ja',
            'kn-IN',
            'km-KH',
            'ko',
            'ky',
            'lo',
            'lv-LV',
            'lt-LT',
            'mk-MK',
            'ms',
            'ml-IN',
            'mr',
            'mn-MN',
            'ne-NP',
            'no',
            'no-NO',
            'fa',
            'pl',
            'pt-BR',
            'pt-PT',
            'ro',
            'ru-RU',
            'sr',
            'si',
            'sk',
            'sl-SI',
            'es-419',
            'es-ES',
            'es-US',
            'sw',
            'sv-SE',
            'ta-IN',
            'te-IN',
            'th',
            'tr',
            'uk',
            'vi',
            'zu'
          ]
        end

        def fix_language_name(name, for_itunes, for_lokalise = false)
          if for_itunes
            if for_lokalise
              name = name.gsub("-","_")
              name = "en" if name == "en_US"
              name = "de" if name == "de_DE"
              name = "es" if name == "es_ES"
              name = "fr" if name == "fr_FR"
              name = "zh_CN" if name == "zh_Hans"
              name = "zh_TW" if name == "zh_Hant"
            else
              name = name.gsub("_","-")
              name = "en-US" if name == "en"
              name = "de-DE" if name == "de"
              name = "es-ES" if name == "es"
              name = "fr-FR" if name == "fr"
              name = "zh-Hans" if name == "zh-CN"
              name = "zh-Hant" if name == "zh-TW"
            end
          else
            if for_lokalise
              name =  name.gsub("-","_")
              name = "tr" if name == "tr_TR"
              name = "hy" if name == "hy_AM"
              name = "my" if name == "my_MM"
              name = "ms" if name == "ms_MY"
              name = "cs" if name == "cs_CZ"
              name = "da" if name == "da_DK"
              name = "et_EE" if name == "et"
              name = "fi" if name == "fi_FI"
              name = "he" if name == "iw_IL"
              name = "hu" if name == "hu_HU"
              name = "ja" if name == "ja_JP"
              name = "ko" if name == "ko_KR"
              name = "ky" if name == "ky_KG"
              name = "lo" if name == "lo_LA"
              name = "lv_LV" if name == "lv"
              name = "lt_LT" if name == "lt"
              name = "mr" if name == "mr_IN"
              name = "no" if name == "no_NO"
              name = "pl" if name == "pl_PL"
              name = "si" if name == "si_LK"
              name = "sl_SI" if name == "sl"
            else
              name = name.gsub("_","-")
              name = "tr-TR" if name == "tr"
              name = "hy-AM" if name == "hy"
              name = "my-MM" if name == "my"
              name = "ms-MY" if name == "ms"
              name = "cs-CZ" if name == "cs"
              name = "da-DK" if name == "da"
              name = "et" if name == "et-EE"
              name = "fi-FI" if name == "fi"
              name = "iw-IL" if name == "he"
              name = "hu-HU" if name == "hu"
              name = "ja-JP" if name == "ja"
              name = "ko-KR" if name == "ko"
              name = "ky-KG" if name == "ky"
              name = "lo-LA" if name == "lo"
              name = "lv" if name == "lv-LV"
              name = "lt" if name == "lt-LT"
              name = "mr-IN" if name == "mr"
              name = "no-NO" if name == "no"
              name = "pl-PL" if name == "pl"
              name = "si-LK" if name == "si"
              name = "sl" if name == "sl-SI"
            end
          end
          name
        end

        #####################################################
        # @!group Documentation
        #####################################################

        def description
          "Upload metadata to lokalise."
        end

        def details
          "This action scans fastlane/metadata folder and uploads metadata to lokalise.com"
        end

        def available_options
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
            FastlaneCore::ConfigItem.new(key: :add_languages,
                                         description: "Add missing languages in lokalise",
                                         optional: true,
                                         is_string: false,
                                         default_value: false,
                                         verify_block: proc do |value|
                                           UI.user_error! "Add languages should be true or false" unless [true, false].include? value
                                         end),
            FastlaneCore::ConfigItem.new(key: :override_translation,
                                         description: "Override translations in lokalise",
                                         optional: true,
                                         is_string: false,
                                         default_value: false,
                                         verify_block: proc do |value|
                                           UI.user_error! "Override translation should be true or false" unless [true, false].include? value
                                         end),
            FastlaneCore::ConfigItem.new(key: :action,
                                         description: "Action to perform (can be update_lokalise_itunes or update_lokalise_googleplay or update_itunes or update_googleplay)",
                                         optional: false,
                                         is_string: true,
                                         verify_block: proc do |value|
                                           UI.user_error! "Action should be update_lokalise_googleplay or update_lokalise_itunes or update_itunes or update_googleplay" unless ["update_lokalise_itunes", "update_lokalise_googleplay", "update_itunes", "update_googleplay"].include? value
                                         end),
            FastlaneCore::ConfigItem.new(key: :release_number,
                                        description: "Release number is required to update google play",
                                        optional: true,
                                        is_string: false),
            FastlaneCore::ConfigItem.new(key: :validate_only,
                                        description: "Only validate the metadata (works with only update_googleplay action)",
                                        optional: true,
                                        is_string: false,
                                        default_value: false,
                                        verify_block: proc do |value|
                                          UI.user_error! "Validate only should be true or false" unless [true, false].include? value
                                        end),
          ]
        end

        def authors
          ["Fedya-L"]
        end

        def is_supported?(platform)
          platform == :ios
        end
      end
    end
  end
end
