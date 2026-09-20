# MyNode Applications

MyNode applications live in `rootfs/standard/usr/share/mynode_apps/<short name>` in this repo. Each app folder holds an icon, a JSON file describing the app, install and service scripts, and optional web files. MyNode loads every app folder it finds there, so an app is shipped by adding its folder to this repo.

## Creating an Application

Run the create script from the repository root:

```
app_sdk/create.py
```

It asks for the application name, a short name, ports, and which services the app depends on, then writes the filled-out template to `rootfs/standard/usr/share/mynode_apps/<short name>`.

After the files are created, update the icon, install script, service file and screenshots, then check the app:

```
app_sdk/create.py check <short name>
```

The check looks for missing files, leftover `FILL_IN` placeholders, and an unpinned or stale download hash.

## Pinning Downloads

Every download must be pinned to a hash, and the pin must be updated whenever `latest_version` changes. Installs fail if a download does not match its pin.

- **Source downloads:** the app is listed in `MARKETPLACE_APPS` in `scripts/print_app_download_hashes.sh`. Run `scripts/print_app_download_hashes.sh <short name>` and paste the printed value into `download_source_sha256` in the app's JSON file.
- **Docker images:** add the image to `MARKETPLACE_DOCKER_IMAGES` in the same script, run it, and paste the printed value into `IMAGE_DIGEST` in the app's install script.

## Testing on a Device

Copy the app folder to a development device and let MyNode pick it up:

```
scp -r rootfs/standard/usr/share/mynode_apps/<short name> admin@<device ip>:/tmp/
```

Then on the device:

```
sudo cp -r /tmp/<short name> /usr/share/mynode_apps/
sudo mynode-manage-apps init
sudo mynode-manage-apps install <short name>
```

The app then appears on the Marketplace page, where it can be installed, enabled and uninstalled like any other app.

Deploying the whole rootfs works too, and picks up changes outside the app folder. Build it with `make rootfs`, copy it to the device as described in the [development guide](development.md), then reload the apps without rebooting:

```
sudo mynode-local-upgrade /tmp/mynode_rootfs_<device type>.tar.gz apps
```

## Publishing an Application

After testing the app and verifying it works well, submit a Pull Request that includes the app folder and its entry in `scripts/print_app_download_hashes.sh`.

We reserve the right to reject any apps for any reason. We will review it as part of the pull request. Some rules:

- No altcoins
- Must have an applicable category
- Must pin all downloads and Docker images
- Must be a quality application

## Application Contents

Each application lives in its own folder under `rootfs/standard/usr/share/mynode_apps/<short name>`. The template app is named "sampleapp" and `create.py` renames every file to the short name of the app being created. Replace *sampleapp* below with your app's short name.

### sampleapp.png
This is the app icon. It should be updated to your app's icon. It must be a PNG file and should have a transparent background. If squarish, it should have rounded corners.

### sampleapp.json
This is the core file that controls your application information. It will require several updates. Details are specified in the Application Data section below.

### sampleapp.service
This is the systemd service file that will launch your application. It can be customised as necessary. Updating the "ExecStart" line is required. Uncomment the `wait_on_*.sh` lines for any services your app depends on. The service runs as the `linux_user` from the JSON file.

### screenshots/*.png
All PNG files within the screenshots folder will be copied to the proper MyNode folders to be displayed on the Marketplace page for the app.

### scripts/install_sampleapp.sh
This script is required. The script will be executed from within the application install directory. The install tarball will have already been downloaded, checked against `download_source_sha256`, and extracted, so files will be present in the current folder. Any steps to install the application must be performed in this script. Docker apps pull their image here with `pull_app_docker_image` and a pinned digest; a commented example is included.

### scripts/uninstall_sampleapp.sh
This script must be present, but content is optional. By default, during uninstall will remove the app installation folder. This script will be run prior to deletion in case any special steps need to be performed.

### scripts/pre_sampleapp.sh
This script must be present, but content is optional. This script will run prior to launching the application.

### scripts/post_sampleapp.sh
This script must be present, but content is optional. This script will run after launching the application.

### www/python/sampleapp.py
This is the python file for handling web interface requests. The web interface is handled by flask and the file comes with a single hander for "/app/sampleapp/info". Additional URLs can be registered for more complex applications if they need to offer additional functionality.

### www/templates/
This is the folder for HTML / Jinja templates to be used by your application. A sample template (sampleapp.html) is provided, but may not be required. Applications can use the standard app template which can be customized via the JSON file, but more advanced apps may require their own templates.

### nginx/https_sampleapp.conf
This file is optional and will be present if your app has a web interface and can be accessed via HTTPS. It may need to be updated depending on your application requirements.

## Application Data

All application data is managed via a JSON file stored in the main application folder. A variety of settings allow control of the application, its dependencies, and how it appears within MyNode. Below is a table of the available settings and a description. Defaults for settings that are left out are set in `rootfs/standard/var/pynode/application_info.py`.

After changing which settings MyNode reads, run `app_sdk/create.py check_doc` to confirm the table below still matches `application_info.py`.

| Setting                    | Type / Default         | Description                                                               |
| -------------------------- | ---------------------- | ------------------------------------------------------------------------- |
| <sub>name                               | <sub>Sample App | <sub>This is the display name of the application. Shown on the Marketplace and Manage Apps pages. |
| <sub>short_name                         | <sub>sampleapp | <sub>This is the "name id" of the app. It identifies the app, its files and its folders. It must match the app folder name. |
| <sub>author                             | <sub>Dictionary | <sub>This defines the "Author" item on the app's Marketplace page. It must contain a "name" and an optional "link" field. |
| <sub>website                            | <sub>Dictionary | <sub>This defines the "Website" item on the app's Marketplace page. It must contain a "name" and an optional "link" field. |
| <sub>category                           | <sub>lightning_app | <sub>This defines the section the app appears within the Marketplace. Options are bitcoin_app, lightning_app, communication, networking, device_management, and uncategorized. |
| <sub>short_description                  | <sub>Sample Data | <sub>This defines the short description of the app on an app tile before it is enabled. Ideally, it should be less than 20 characters. |
| <sub>description                        | <sub>Sample Data | <sub>This is the long description of an application that is displayed on the app's Marketplace page. It can be a single string or a list of strings to be displayed as paragraphs. |
| <sub>linux_user                         | <sub>sampleapp | <sub>The Linux user the app is installed and run as. It is created if needed and added to the bitcoin group (and docker group for Docker apps). Must match User= in the service file. Defaults to bitcoin if not set. |
| <sub>latest_version                     | <sub>v0.0.1 | <sub>The version of the app to install. Replaces {VERSION} in download URLs. |
| <sub>minimum_debian_version             | <sub>10 | <sub>The minimum Debian version required to install the app. |
| <sub>supported_archs                    | <sub>null | <sub>This determines which device architectures are supported. Default is null which means all architectures are supported. Otherwise, this is a list of supported architectures, like ["aarch64","x86_64"]. |
| <sub>installed_app_dependencies         | <sub>[] | <sub>A list of app short names that must be installed before this app can be installed. |
| <sub>download_skip                      | <sub>false | <sub>This defines whether or not a download is required to install the app. Docker apps typically set this to true and pull their image in the install script. |
| <sub>download_type                      | <sub>"source" | <sub>This defines the type of content being downloaded. It can be "source" or "binary". |
| <sub>download_source_url                | <sub>Sample Data | <sub>This is the URL to download the application and is typically a link to the GitHub source tar.gz file for a tag or release. It will be extracted and installed prior to running the apps install script. |
| <sub>download_source_sha256             | <sub>"v0.0.1 FILL_IN_SHA256" | <sub>The pinned "&lt;version&gt; &lt;sha256&gt;" of the source download. Installs fail if the download does not match. Generate it with scripts/print_app_download_hashes.sh in the MyNode repo and update it with every version change. |
| <sub>download_binary_url                | <sub>Dictionary | <sub>This is a dictionary of architectures to URL to download the application and is typically a link to the GitHub binary tar.gz file for a tag or release. It will be extracted and installed prior to running the apps install script. |
| <sub>install_env_vars                   | <sub>Dictionary | <sub>If any additional data is needed during the install process. This dictionary of key/value pairs will be available as env variables. |
| <sub>supports_app_page                  | <sub>true | <sub>Not currently used by MyNode. |
| <sub>supports_testnet                   | <sub>false | <sub>Indicates if the app supports Bitcoin testnet. If not, the app will be disabled when in testnet mode. |
| <sub>http_port                          | <sub>8000 | <sub>Indicates the HTTP port to be used by the application. This should be set for all web apps. The port will be automatically opened. |
| <sub>https_port                         | <sub>8001 | <sub>Indicates the HTTPS port to be used by the application. Typically, the HTTP port plus one. |
| <sub>extra_ports                        | <sub>[] | <sub>A list of additional ports to open in the firewall. |
| <sub>requires_bitcoin                   | <sub>true | <sub>This indicates a dependency on Bitcoin. If true, Bitcoin must be running before the application will start. This should be true for most apps. Some device management apps may set this to false. |
| <sub>requires_docker_image_installation | <sub>false | <sub>This indicates a dependency on Docker. If true, the app runs as a Docker container and is installed by the docker image install script. |
| <sub>requires_electrs                   | <sub>false | <sub>This indicates a dependency on Electrum Server. If true, Electrum Server must be enabled and running before the app can be enabled and started. |
| <sub>requires_lightning                 | <sub>true | <sub>This indicates a dependency on Lightning. If true, Lightning must be setup and running before the app can be enabled and started. |
| <sub>show_on_marketplace_page           | <sub>true | <sub>This toggles whether or not the app is displayed on the Marketplace page. Defaults to show_on_application_page. |
| <sub>show_on_application_page           | <sub>true | <sub>This toggles whether or not the app is displayed in the list of apps on the Manage Applications page. |
| <sub>show_on_homepage                   | <sub>true | <sub>This toggles whether or not the app is displayed as a tile on the homepage. |
| <sub>show_on_status_page                | <sub>true | <sub>This toggles whether or not the app is shown on the status page. All apps that have a log available should have this set to true. |
| <sub>hide_status_icon                   | <sub>false | <sub>This toggles whether or not the status icon (color dot) is displayed for the application. This should be false for all applications that run as a service. |
| <sub>log_file                          | <sub>App log | <sub>The log file shown on the status and app pages. Defaults to the app's log file if one exists. |
| <sub>journalctl_log_name               | <sub>null | <sub>The systemd unit to read logs from with journalctl, used when the app has no log file. |
| <sub>app_tile_name                      | <sub>"Sample Application" | <sub>This defines the display name of the application on the app tile on the home page. Some apps require a shorter name to fit on the app tile. |
| <sub>app_tile_running_status_text       | <sub>"Running" | <sub>This defines the status text of an application when it has been enabled and is running properly according to systemd. |
| <sub>app_tile_button_text               | <sub>"Info" | <sub>This defines the text of the link displayed in the application tile on the home page. |
| <sub>app_tile_button_href               | <sub>"/app/sampleapp/info" | <sub>This defines the destination of the link displayed on the application tile on the home page. |
| <sub>app_tile_button_open_app_directly | <sub>false | <sub>Makes the app tile button open the app itself instead of app_tile_button_href. Requires a port to be set. |
| <sub>app_page_show_open_button          | <sub>true | <sub>This toggles whether or not the Open button is displayed on the application page. It should be true for web-based applications. |
| <sub>app_page_content                   | <sub>Sample Data | <sub>This defines the application page content if using the generic application page (ex. /app/[app]/info). It is a list of dictionaries with two items - heading and content. Content can be a list of string to be displayed as paragraphs. |
| <sub>app_page_additional_buttons       | <sub>[] | <sub>Extra buttons on the app page. A list of dictionaries with a title and an href. |
| <sub>login_username                     | <sub>"" | <sub>The username shown on the app page next to the app password, for apps whose pre script sets a password with save_app_default_password (see mynode_functions.sh). |
| <sub>can_uninstall                      | <sub>true | <sub>Indicates if the application can be uninstalled. |
| <sub>can_reinstall                      | <sub>true | <sub>Indicates if the application can be re-installed. |
| <sub>can_enable_disable                 | <sub>true | <sub>Indicates if the application is a service that can be enabled and disabled. Set to false for CLI tools. |
| <sub>data_manageable                    | <sub>false | <sub>Shows a Reset Data button on the app page, which deletes the app's data folder (/mnt/hdd/mynode/[app]). |
| <sub>is_beta                            | <sub>false | <sub>Indicates if an app is "beta" quality. If true, adds a beta icon in the UI. |
| <sub>is_premium                         | <sub>false | <sub>Indicates if this app is available only for premium users. |
| <sub>homepage_section                   | <sub>apps | <sub>The homepage section the app tile is shown in. |
| <sub>homepage_order                     | <sub>91 | <sub>This dictates the order of apps shown on the home page. Should be 91+. |
| <sub>app_type                           | <sub>custom | <sub>This indicates the type of application. For future use. |
| <sub>sdk_version                        | <sub>2 | <sub>The app format version. New apps use 2. |

The full sample is in [../app_sdk/sampleapp/sampleapp.json](../app_sdk/sampleapp/sampleapp.json).
