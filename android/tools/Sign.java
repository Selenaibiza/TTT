import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;

import java.io.File;
import java.io.FileInputStream;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 *  Sign.java — امضای APK با کتابخانهٔ apksig (جایگزین دستور apksigner)
 *
 *  استفاده:
 *    java -cp apksig.jar;. Sign <in.apk> <out.apk> <keystore> <pass> <alias>
 */
public class Sign {

    public static void main(String[] args) throws Exception {
        String inApk    = args[0];
        String outApk   = args[1];
        String ksPath   = args[2];
        String storePass = args[3];
        String alias    = args[4];

        char[] pass = storePass.toCharArray();

        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        try (FileInputStream fis = new FileInputStream(ksPath)) {
            keyStore.load(fis, pass);
        }

        PrivateKey key = (PrivateKey) keyStore.getKey(alias, pass);
        X509Certificate cert = (X509Certificate) keyStore.getCertificate(alias);
        if (key == null || cert == null) {
            throw new IllegalStateException("کلید یا گواهی در keystore پیدا نشد (alias=" + alias + ")");
        }

        List<X509Certificate> certChain = new ArrayList<>();
        certChain.add(cert);

        ApkSigner.SignerConfig signerConfig =
                new ApkSigner.SignerConfig.Builder(alias, key, certChain).build();

        ApkSigner signer = new ApkSigner.Builder(Collections.singletonList(signerConfig))
                .setInputApk(new File(inApk))
                .setOutputApk(new File(outApk))
                .setV1SigningEnabled(true)
                .setV2SigningEnabled(true)
                .setV3SigningEnabled(true)
                .setMinSdkVersion(21)
                .build();

        signer.sign();
        System.out.println("  SIGNED  -> " + outApk);

        // ---------- بررسی ----------
        ApkVerifier.Result result = new ApkVerifier.Builder(new File(outApk))
                .build()
                .verify();

        System.out.println("  VERIFIED: " + result.isVerified());
        if (!result.isVerified()) {
            for (ApkVerifier.IssueWithParams issue : result.getErrors()) {
                System.out.println("    ERROR: " + issue);
            }
            System.exit(3);
        }
        System.out.println("  schemes : v1=" + result.isVerifiedUsingV1Scheme()
                + " v2=" + result.isVerifiedUsingV2Scheme()
                + " v3=" + result.isVerifiedUsingV3Scheme());
    }
}
