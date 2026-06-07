# Terranix configuration for the UniFi Express 7 at 192.168.1.1.
# Credentials come from the environment (set by the unifi-tofu wrapper):
#   UNIFI_API, UNIFI_API_KEY, UNIFI_INSECURE, TF_VAR_wifi_passphrase
{
  terraform.required_providers.unifi = {
    source = "ubiquiti-community/unifi";
    version = "~> 0.41.0";
  };

  provider.unifi = { };

  variable.wifi_passphrase = {
    type = "string";
    sensitive = true;
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
