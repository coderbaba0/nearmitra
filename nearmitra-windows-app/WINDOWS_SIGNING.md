# Windows publisher identity

The installer UI and Windows installed-app entry use `flutterfever.com` as Publisher.
This is branding metadata. Windows UAC's Verified publisher is derived from the
executable's trusted Authenticode signing certificate, not that registry value,
the setup HTML, the website URL or the application's icon.

The 2.1.15 build is **unsigned** because no code-signing certificate was available.
It therefore still displays Unknown publisher in UAC. Its branding change must
not be described as a verified-publisher fix.

To ship with a verified publisher, obtain a trusted code-signing certificate or
an identity-validated signing service. The certificate's verified subject must
represent the publisher. UAC may show a legal organization/person name rather
than the literal website domain; `/du https://flutterfever.com` does not override
that identity. A website HTTPS certificate is not a substitute. A self-signed
certificate does not establish trust on other people's computers.

## Certificate-store signing

Use a certificate with an accessible private key in the current Windows user's
Personal/My certificate store and Windows SDK SignTool. Keep keys outside the
repository. Configure an authorized publisher certificate by thumbprint:

```bat
set "NEARMITRA_SIGN_THUMBPRINT=YOUR_CERTIFICATE_THUMBPRINT"
set "NEARMITRA_SIGNTOOL=C:\Program Files (x86)\Windows Kits\10\bin\SDK_VERSION\x64\signtool.exe"
build-installer.bat
```

`build-installer.bat` signs and verifies the app before embedding it in setup,
then signs and verifies the completed setup. It uses SHA256 and an RFC3161
SHA256 timestamp. A configured signing/verification failure aborts the build;
it never silently falls back to unsigned output. Without a configured
thumbprint, the script prints an unsigned-build notice. `NEARMITRA_SIGN_TIMESTAMP`
can override the timestamp endpoint. Hardware-token certificates may request
their vendor's PIN; no private key or PIN is read by the build scripts.

The installed native Uninstall.exe is a byte-for-byte copy of setup, retaining
its signature. Regenerate SHA256SUMS.txt after signing. Cloud signing services
require their provider-specific integration instead of assuming a local key.

References:
- https://learn.microsoft.com/windows/win32/seccrypto/time-stamping-authenticode-signatures
- https://learn.microsoft.com/windows/win32/seccrypto/signtool
