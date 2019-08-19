# Lokalise Fastlane Actions for Android

Fastlane actions for integrating Lokalise into your Android project using Fastlane.

All Android actions based on APIs V2

## Note

These are Fastlane actions, not plugins. Add them to `fastlane/actions` folder in the root of your project.

## lokalise_download

This action downloads strings.xml files to you main resources folder `./app/src/main/res`.

>That will replace your local strings.xml file with the latest version from lokalise project. 
>So make sure to call lokalise_upload first to don't miss any added keys.

Parameters:

- `api_token`. Your API token. Can be set up using enviromental parameter `LOKALISE_API_TOKEN`
- `project_identifier`. Your Project ID. Can be set up using enviromental parameter `LOKALISE_PROJECT_ID`
- `languages`. Languages to download *(must be passed as array of strings)* Ex. `["en", "ar"]`.

Sample:
```
lokalise_download(
    api_token: "YOUR_API_TOKEN",
    project_identifier: "YOUR_PROJECT_ID",
    languages: ["en", "ar"]
)
        
```

## lokalise_upload

This action uploads the new keys from your local strings.xml files to lokalise project.

- `api_token`. Your API token. Can be set up using enviromental parameter `LOKALISE_API_TOKEN`
- `project_identifier`. Your Project ID. Can be set up using enviromental parameter `LOKALISE_PROJECT_ID`
- `languages`. Languages to download *(must be passed as array of strings)* Ex. `["en", "ar"]`.

Sample:
```
lokalise_upload(
    api_token: "YOUR_API_TOKEN",
    project_identifier: "YOUR_PROJECT_ID",
    languages: ["en", "ar"]
)
        
```


_All this actions are the basic ones, and can be enhanced for supporting flavors_
