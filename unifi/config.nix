# Terranix configuration for the UniFi Express 7 at 192.168.1.1.
# Credentials come from the environment (set by the unifi-plan/apply apps):
#   UNIFI_API, UNIFI_API_KEY, UNIFI_INSECURE,
#   TF_VAR_wifi_passphrase, TF_VAR_unifi_api_key
{ lib, ... }:

let
  # Resolve these to 0.0.0.0 on the gateway's DNS (LG TV ads/tracking).
  # The unifi provider has no static-DNS resource, so these go through the
  # controller's v2 API via the generic restapi provider.
  blockedDomains = [
    "ad.lgappstv.com"
    "ads.lgads.tv"
    "lgads.tv"
    "ads.lgsmartad.com"
    "us.ad.lgsmartad.com"
    "kr.ad.lgsmartad.com"
    "info.lgsmartad.com"
    "ibis.lgappstv.com"
    "lgad.cjpowercast.com"
  ];
in
{
  terraform.required_providers.unifi = {
    source = "ubiquiti-community/unifi";
    version = "~> 0.41.0";
  };
  terraform.required_providers.restapi = {
    source = "Mastercard/restapi";
    version = "~> 2.0";
  };

  provider.unifi = { };

  provider.restapi = {
    uri = "https://192.168.1.1/proxy/network/v2/api/site/default";
    insecure = true;
    write_returns_object = true;
    id_attribute = "_id";
    headers."X-API-KEY" = "\${var.unifi_api_key}";
  };

  variable.wifi_passphrase = {
    type = "string";
    sensitive = true;
  };
  variable.unifi_api_key = {
    type = "string";
    sensitive = true;
  };

  # LG C6 TV: known to the network but blocked from the internet.
  # LAN_IN only governs routed traffic, so same-subnet control/casting
  # still works; only WAN access is dropped.
  resource.unifi_client = {
    lg_tv_wireless = {
      mac = "70:3e:76:18:63:6c";
      name = "LG TV (wireless)";
      fixed_ip = "192.168.1.200";
    };
    lg_tv_wired = {
      mac = "d0:cd:bf:1a:34:80";
      name = "LG TV (wired)";
      fixed_ip = "192.168.1.201";
    };
  };

  resource.unifi_firewall_rule = {
    block_lg_tv_wireless = {
      name = "Block LG TV internet (wireless)";
      ruleset = "LAN_IN";
      rule_index = 20000;
      action = "drop";
      src_mac = "70:3e:76:18:63:6c";
      protocol = "all";
      enabled = true;
      logging = false;
      state_established = false;
      state_invalid = false;
      state_new = false;
      state_related = false;
    };
    block_lg_tv_wired = {
      name = "Block LG TV internet (wired)";
      ruleset = "LAN_IN";
      rule_index = 20001;
      action = "drop";
      src_mac = "d0:cd:bf:1a:34:80";
      protocol = "all";
      enabled = true;
      logging = false;
      state_established = false;
      state_invalid = false;
      state_new = false;
      state_related = false;
    };
  };

  resource.restapi_object = lib.listToAttrs (map
    (domain: {
      name = "dns_block_${lib.replaceStrings [ "." ] [ "_" ] domain}";
      value = {
        path = "/static-dns";
        # The v2 API has no GET-by-id (405), so reads search the collection
        read_path = "/static-dns";
        read_search = {
          search_key = "key";
          search_value = domain;
        };
        data = builtins.toJSON {
          record_type = "A";
          key = domain;
          value = "0.0.0.0";
          enabled = true;
        };
        # Reads return server-added fields (_id, ttl, ...) that would diff
        # against our minimal data forever. These records never change; to
        # alter one, rename the resource (or tofu taint) to recreate it.
        lifecycle.ignore_changes = [ "data" ];
      };
    })
    blockedDomains);

  # Default LAN: 192.168.1.0/24
  resource.unifi_network.default = {
    name = "Default";
    subnet = "192.168.1.1/24";
    domain_name = "localdomain";
    multicast_dns = true;
    ipv6_interface_type = "none";
    lte_lan = false;
    dhcp_server = {
      enabled = true;
      start = "192.168.1.6";
      stop = "192.168.1.254";
      conflict_checking = false;
    };
  };

  resource.unifi_wlan.fluffcorp = {
    name = "FluffCorp";
    security = "wpapsk";
    passphrase = "\${var.wifi_passphrase}";
    network_id = "\${unifi_network.default.id}";
    wlan_band = "both";
    wlan_bands = [ "2g" "5g" "6g" ];
    bss_transition = true;
    minrate_setting_preference = "auto";
    minimum_data_rate_2g_kbps = 1000;
    minimum_data_rate_5g_kbps = 6000;
    mac_filter = {
      enabled = false;
      policy = "allow";
    };
    # Workaround: with no schedule blocks the provider serializes
    # schedule_with_duration as null, which this firmware rejects (400).
    schedule = [ ];
    wpa3_support = true;
    wpa3_transition = true;
    pmf_mode = "optional";
    # Existing default user/AP groups (not yet managed here)
    user_group_id = "69d62d009cb8c56056481c94";
    ap_group_ids = [ "69d62d009cb8c56056481c99" ];
    ap_group_mode = "all";
  };
}
