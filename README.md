# About danebot

The `danebot` shell script is a small wrapper around `certbot` that:

1. Calls certbot as needed to do automated certificate updates, just
   like certbot does.
2. Keeps TLSA records stable by normally reusing the current key
   for certificate renewals.
3. Supports key rollover, after ensuring that matching TLSA records
   are already published.
4. Supports multiple certbot *lineages* (renewable certificates). Some
   of the lineages can be simple pass-throughs to `certbot` with no
   `danebot` indirection to ensure TLSA record consistency.

Using `danebot` should ensure you avoid outages due to mismatched TLSA
records as a result of Let's Encrypt automated certificate renewal.

## Important notes:

- You **must** use danebot in place of certbot -- Specifically,
  disable the cron or other process that invokes certbot and
  instead use danebot exclusively.

# Installation

## Install certbot

`certbot` must be installed on the system first (potentially using
`dnf`, `apt-get` or other package management tool).  The `bash`
shell must also be installed.

## Install danebot

Install `danebot` to /usr/local/bin or other preferred path.

Optionally change some of the default parameters discussed at the top
of `danebot` by creating a `/etc/default/danebot file with variable
overrides as desired (this supports `bash` syntax: `danebot` is a
`bash` shell script).

### Setting KEYALG and KEYOPTS

For default key roller parameters, these defaults may be changed in
/etc/default/danebot

    KEYALG="rsa"
    KEYOPTS=(rsa_keygen_bits:2048)
    
### which local nameserver to query

IP address of trusted validating DNS resolver, should not be "too" remote!
Needed to check TLSA record presence.  Ideally loopback.

    NS=127.0.0.1

# Usage

## Initialization

1. Use `certbot` to create and initialise any certificate *lineages* you want
   managed on your system.  (Changing the list of DNS names covered by a certificate
   lineage is not yet supported by `danebot`, you can run `certbot` interactively to
   do that).

2. Run `danebot init` so it can find and start managing `certbot`'s
   certificates.  If you manage more than one certificate *lineage*,
   you can specify a list of lineage names to convert to `danebot`.

<!--
Q: does `danebot` spit out TLSA records here?
A: Just a suggested "3 1 1" record, for an unspecified DNS name
-->

## Certificate update automation

Pick whether you want to call `danebot` from systemd or cron.  Either
way, make sure you disable any `certbot renew` cron or other scripts.

### using systemd integration

For systemd, install `danebot.service` and `datebot.timer` in
`/lib/systemd/system/`, and enable them.

### Using cron:

1. Run `danebot renew` in a weekly-ish cron job.  It will continue to
   reuse your existing private key for your certificates (see
   below for rolling your keys).
   
2. While `certbot` hooks are already non-reliable (don't retry later
   on failure to complete, ...), they're even more so a poor fit with
   `danebot`, because when managed by `danebot`, `certbot` only puts the new
   certificate in a staging directory, which is post-processed by `danebot`.
   When certbot hooks run, the new certificate chain is not yet deployed.
   Therefore, you'll need run additional commands after `danebot` is done,
   that check for recent changes in the "live" certificate files, and
   take appropriate actions.

## Rolling your private key to a new key

To have `danebot` start the process of rolling a given *lineage* to a new
private PKIX key:

1. Create a `dane-ee` file in the `staging/`*lineage* subdirectory of the
   `letsencrypt` configuration directory.  This file must list one line per
   monitored TLSA record set.  Each line has two fields, a DANE matching type
   and an DNS FQDN where the TLSA record is expected to be found.  Example:

      ```
      1 _25._tcp.smtp.acme.example
      ```

   With this setting, new keys will only be used once a matching `3 1 1`
   TLSA record is published for `_25._tcp.smtp.acme.example`.  If your
   certificate covers multiple logical MTA names, add a line for each.
   Best practice is to use a single MX hostname for multiple domains,
   rather than a separate one for each domain, then just one TLSA record
   is enough.

   You can also require that the Let's Encrypt issued certificate have a set of
   expected DNS names by creating a `dnsnames` file in the same
   *lineage*-specific staging directory.  List one DNS name per line.  New
   certificates will only be made "live" when all the required names are present.

2. Run `danebot newkey <lineage>` by hand.  You must specify exactly one *lineage*
   name.  This will create the new key but will not start using it yet.  It
   will output a new `TLSA` record.  You should **add** this new TLSA record to
   all the associated `_port._tcp.server.example` DNS RRsets (typically just one,
   when the certificate covers just one hostname).  **Do not remove the TLSA records
   matching the original key just yet, you're still using the old key.**

3. Continue running the `danebot renew` cron job as before.  `danebot` will
   monitor for the appearance of the expected `TLSA` records and wait at
   least 2 more days before calling `certbot` to switch to using the new key
   for creating certificates.

4. After `danebot` switches to the new key, you can remove the older TLSA
   records from DNS (making sure to remove the old and not the new ones).

# Usage

## Running it for the first time

# How it works

Under the hood, `danebot` creates lineage-specific `staging` sub-directories
named `/etc/letsencrypt/staging/`*lineage-name*.  Certificates and keys
generated by `certbot` are only copied to the `live` directory after basic
validation.  For applications that support atomically loading both the private
key and the certificate chain from the same file, `danebot` also atomically
updates a `combo.pem` file in the lineage-specific `live/` directory.  The
`combo.pem` file will contain the private key followed by the certificate
chain with the leaf certificate before the rest of the chain.

If you decide to disable `danebot` and go back to `certbot`, don't forget
to go back to using `privkey.pem` and `fullchain.pem`, as `certbot` will
not update `combo.pem`.

By default `danebot` keeps the underlying public/private key pair fixed
across certificate updates, allowing the extant TLSA records, either or
both of:

* 3 1 1: i.e. `DANE-EE(3) SPKI(1) SHA2-256(1)` _sha256(pubkey)_
* 3 1 2: i.e. `DANE-EE(3) SPKI(1) SHA2-512(2)` _sha512(pubkey)_

to remain unchanged across the certificate update.  However, at you discretion,
`danebot` also supports worry-free key rollover.  You can stage a _next_ key
that will only replace the _current_ key once the appropriate additional TLSA
records have been in place long enough for stale cached copies of the TLSA
records to have expired.  Once the new TLSA records have been published for the
minimum time, a new certificate chain is obtained with the staged _next_ as the
new _current_ key.

**NOTE**: The safety-net is only in place if you create a `dane-ee` file in the
lineage-specific staging directory with the expected TLSA record matching
type(s) and DNS locations.  Otherwise the new key will be used on the next
renew cycle even if no matching TLSA records have been published.
