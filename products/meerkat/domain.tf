# meerkat's only DNS record is the module's own cloudflare_dns_record.app,
# which points meerkat.protoapp.xyz at the distribution.
#
# The www record that used to live here pointed www.protoapp.xyz at this
# distribution, from when meerkat served the umbrella apex. It was deleted when
# meerkat moved to its subdomain: protoapp.xyz and www.protoapp.xyz now belong
# to no product and are free for an umbrella page. Deliberately no redirect from
# the old names — these are personal projects with no inbound links worth
# preserving.
