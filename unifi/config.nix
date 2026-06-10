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

  # Helpers for patching in resources the unifi provider doesn't model,
  # via the generic restapi provider. Two shapes show up against the UniFi
  # controller API; one factory each.

  # v2 collection object (e.g. static DNS). The v2 API has no GET-by-id
  # (405), so reads search the collection by a unique field. ignore_changes
  # guards server-added fields (_id, ttl, ...) from diffing against our
  # minimal data forever; to change one, rename the resource or tofu taint.
  mkV2Object = { path, searchKey, data }: {
    inherit path;
    read_path = path;
    read_search = {
      search_key = searchKey;
      search_value = data.${searchKey};
    };
    data = builtins.toJSON data;
    lifecycle.ignore_changes = [ "data" ];
  };

  # v1 site setting (e.g. the LCM display). Settings are singletons keyed
  # by `key` that always exist: create and update are both PUTs to the
  # fixed path, and destroy is a harmless GET (settings can't be deleted).
  # v1 wraps reads in {meta, data: [...]} and adds server fields, so we set
  # object_id explicitly and ignore_changes on data. To change a value,
  # edit it here and `tofu taint restapi_object.<name>` to PUT-recreate.
  mkV1Setting = key: data: {
    provider = "restapi.v1";
    object_id = key;
    path = "/rest/setting/${key}";
    create_method = "PUT";
    create_path = "/rest/setting/${key}";
    update_method = "PUT";
    update_path = "/rest/setting/${key}";
    read_path = "/rest/setting/${key}";
    destroy_method = "GET";
    destroy_path = "/rest/setting/${key}";
    data = builtins.toJSON ({ inherit key; } // data);
    lifecycle.ignore_changes = [ "data" ];
  };
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

  provider.restapi = [
    {
      uri = "https://192.168.1.1/proxy/network/v2/api/site/default";
      insecure = true;
      write_returns_object = true;
      id_attribute = "_id";
      headers."X-API-KEY" = "\${var.unifi_api_key}";
    }
    # Some settings (e.g. the LCM display) only exist in the legacy v1 API.
    # v1 wraps responses in {meta, data: [...]}, so resources using this
    # alias must set object_id explicitly instead of relying on id_attribute.
    {
      alias = "v1";
      uri = "https://192.168.1.1/proxy/network/api/s/default";
      insecure = true;
      headers."X-API-KEY" = "\${var.unifi_api_key}";
    }
  ];

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

  # Resolve LG TV ad/tracking domains to 0.0.0.0 on the gateway's DNS.
  resource.restapi_object = lib.listToAttrs (map
    (domain: {
      name = "dns_block_${lib.replaceStrings [ "." ] [ "_" ] domain}";
      value = mkV2Object {
        path = "/static-dns";
        searchKey = "key";
        data = {
          record_type = "A";
          key = domain;
          value = "0.0.0.0";
          enabled = true;
        };
      };
    })
    blockedDomains) // {
    # Turn the Express 7's LCM touchscreen off. enabled is the display-off
    # switch; the rest is retained from the controller defaults so flipping
    # it back to true is a one-line change.
    lcm_display = mkV1Setting "lcm" {
      enabled = false;
      brightness = 80;
      idle_timeout = 300;
      sync = true;
      touch_event = true;
    };
  };

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
