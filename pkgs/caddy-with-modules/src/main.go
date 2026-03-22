package main

import (
	caddycmd "github.com/caddyserver/caddy/v2/cmd"

	// plug in Caddy modules here
	_ "github.com/caddyserver/caddy/v2/modules/standard"
	_ "github.com/greenpau/caddy-security"
	_ "github.com/mholt/caddy-ratelimit"
	_ "github.com/caddyserver/cache-handler"
)

func main() {
	caddycmd.Main()
}
