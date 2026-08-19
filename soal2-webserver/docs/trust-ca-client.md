# Trusting the SEVIMA CA on your laptop

Items C.3.c and D.4 require that "localhost and your laptop can access without any warning".

Two sides must be satisfied:

| Side | Handled by | How |
|---|---|---|
| Server / localhost | `50-ca.sh` | CA installed into `/usr/local/share/ca-certificates/`, then `update-ca-certificates` |
| Laptop | **you, manually** | steps below |

The laptop side is deliberately not automated. Installing a root CA changes the system trust store,
and a wrong root CA can be used to intercept all of that machine's HTTPS traffic. That is a
decision to make consciously, not to hand to a script.

## 1. Fetch the CA file from the server

```
scp -P 2025 root@<server-ip>:/root/sevima-ca.crt ~/Downloads/sevima-ca.crt
```

Verify the fingerprint matches the one on the server before trusting it:

```
openssl x509 -in ~/Downloads/sevima-ca.crt -noout -fingerprint -sha256
```

## 2. Point the domain names at the server

Add to `/etc/hosts` on your laptop, replacing `<server-ip>`:

```
<server-ip>  www.sevima.site utara.sevima.site timur.sevima.site barat.sevima.site sevima.site
```

If the server runs in a local VM with ports forwarded to localhost, use `127.0.0.1` instead.

## 3. Trust the CA

### macOS

```
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain ~/Downloads/sevima-ca.crt
```

This prompts for an admin password and modifies the System Keychain. Quit and reopen the browser
afterwards — Chrome reads the Keychain at startup.

Firefox keeps its own trust store: Settings → Privacy & Security → Certificates → View
Certificates → Authorities → Import, then tick "Trust this CA to identify websites".

To revoke later:

```
sudo security delete-certificate -c "SEVIMA CA" /Library/Keychains/System.keychain
```

### Debian / Ubuntu laptop

```
sudo cp ~/Downloads/sevima-ca.crt /usr/local/share/ca-certificates/sevima-ca.crt
sudo update-ca-certificates
```

### Windows

Run from an Administrator Command Prompt:

```
certutil -addstore -f "ROOT" sevima-ca.crt
```

## 4. Prove there is no warning

```
curl -v https://www.sevima.site/
curl -v https://barat.sevima.site:4435/
```

No `-k` allowed. The line to look for:

```
*  SSL certificate verify ok.
```

Then open both URLs in a browser — the padlock must be normal, with no warning interstitial.
Capture the certificate detail view showing the issuer `SEVIMA CA` for the report.

**Order matters for barat.** Open `http://barat.sevima.site:8080` and capture the 301 redirect
*before* you ever load its HTTPS URL. HSTS applies per host and ignores the port, so once the
browser has seen the HTTPS site it will never send plain HTTP to that host again on any port, and
the redirect can no longer be demonstrated.

## After grading

Revoke this CA once the lab is no longer needed. A root CA still trusted while its private key sits
on a practice VM is a real risk, not a formality.
