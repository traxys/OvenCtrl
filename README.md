# Oven Controller (for WebRTC)

This server can be used as a controller for [OvenMediaEngine](https://github.com/AirenSoft/OvenMediaEngine) in order to implement the following features:

- Streamer authentication: Allow only certain people to stream to the OVE server
- Room management: List all available "rooms" (or distinct streams) and allow only certain streamers to access them
- Room authentication: Add a password on rooms

In order to configure the server the following block needs to be added to the OVE `Server.xml` config:

```xml
<Server version="8">
    <!-- CONFIG... -->

    <VirtualHosts>
        <VirtualHost>
            <!-- Virtual Host Config... -->
            <AdmissionWebhooks>
                <ControlServerUrl>http://<host>/oven/admission</ControlServerUrl>
                <SecretKey></SecretKey>
                <Timeout>3000</Timeout>
                <Enables>
                    <Providers>webrtc</Providers>
                    <Publishers>webrtc</Publishers>
                </Enables>
            </AdmissionWebhooks>
        </VirtualHost>
    </VirtualHosts>
</Server>
```

OBS needs to be configured to output to WHIP using the following url: `http://<host>/app/<room>?direction=whip&key=<streamer key>&name=<streamer name>`.

Note that the server _should_ be deployed using HTTPS as query parameters contain the passwords!

The controller must be passed a configuration file as a first parameter.
Here is an example configuration file:
```toml
# Each value can be passed through environment variables

# Address of the OVE server
external_host = "localhost:3333"
# Should we access the OVE server with TLS?
external_tls = false

# List of streamer names (<name> = <key>)
[streamers]
traxys = "1234" # Can be supplied with OVEN_CTRL_STREAMERS_traxys=1234

# Allowed rooms for each streamer (<name> = [<rooms>])
[allowed_streams]
traxys = ["foo", "stream"]

# Passwords for each room (<room> = <password>)
[rooms]
stream = "password" # Can be supplied with OVEN_CTRL_ROOMS_stream=password
```
