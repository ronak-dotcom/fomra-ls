/**
 * Vercel build step: installs the Flutter SDK and compiles the actual web
 * app from source, instead of relying on a manually pre-built `build/web`
 * that someone has to remember to regenerate and commit locally.
 *
 * Vercel's build machines have full internet access (unlike some sandboxed
 * dev environments), so downloading the Flutter SDK/engine here works fine.
 *
 * The SDK must come from the official prebuilt archive so Flutter has valid
 * release metadata during dependency resolution. A bare git clone can report
 * `0.0.0-unknown`, which breaks pub solves for packages that declare a minimum
 * Flutter SDK version.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..');
const flutterDir = path.join(repoRoot, '.flutter-sdk');
const flutterBin = path.join(flutterDir, 'bin');
// Must be >= the highest `flutter:` constraint in the dependency tree. The
// `record` 7.x packages require Flutter >= 3.44.0 / Dart ^3.12.0, so an older
// pin (previously 3.35.5) fails `flutter pub get` before it ever compiles.
const flutterArchiveVersion = '3.44.2';
// Records which SDK version the cached .flutter-sdk holds, so bumping the
// version above forces a fresh install instead of silently reusing an old SDK.
const flutterStampFile = path.join(flutterDir, '.installed-version');
const flutterPlatform = process.platform;
const flutterArch = process.arch;

function flutterArchiveInfo() {
  if (flutterPlatform === 'linux' && flutterArch === 'x64') {
    return {
      url: `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutterArchiveVersion}-stable.tar.xz`,
      extractFolder: 'flutter',
    };
  }

  if (flutterPlatform === 'linux' && flutterArch === 'arm64') {
    return {
      url: `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_arm64_${flutterArchiveVersion}-stable.tar.xz`,
      extractFolder: 'flutter',
    };
  }

  if (flutterPlatform === 'darwin' && flutterArch === 'arm64') {
    return {
      url: `https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_${flutterArchiveVersion}-stable.zip`,
      extractFolder: 'flutter',
    };
  }

  if (flutterPlatform === 'darwin' && flutterArch === 'x64') {
    return {
      url: `https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_${flutterArchiveVersion}-stable.zip`,
      extractFolder: 'flutter',
    };
  }

  throw new Error(`Unsupported Flutter build host: ${flutterPlatform}/${flutterArch}`);
}

function run(cmd, opts = {}) {
  console.log(`$ ${cmd}`);
  execSync(cmd, { stdio: 'inherit', cwd: repoRoot, timeout: 8 * 60 * 1000, ...opts });
}

function extractArchive(archivePath, extractDir, archiveUrl) {
  if (archiveUrl.endsWith('.zip')) {
    run(`unzip -q "${archivePath}" -d "${extractDir}"`);
  } else {
    run(`tar -xf "${archivePath}" -C "${extractDir}"`);
  }
}

function installFlutter() {
  if (fs.existsSync(path.join(flutterBin, 'flutter'))) {
    const cached = fs.existsSync(flutterStampFile)
      ? fs.readFileSync(flutterStampFile, 'utf8').trim()
      : '';
    if (cached === flutterArchiveVersion) {
      console.log(`Using cached Flutter SDK ${cached} at`, flutterDir);
      return;
    }
    console.log(
      `Cached Flutter SDK is "${cached || 'unknown'}", need ${flutterArchiveVersion} — reinstalling.`,
    );
    fs.rmSync(flutterDir, { recursive: true, force: true });
  }

  const archiveInfo = flutterArchiveInfo();
  console.log(`Installing Flutter SDK ${flutterArchiveVersion} from the official release archive...`);
  fs.rmSync(flutterDir, { recursive: true, force: true });
  fs.mkdirSync(flutterDir, { recursive: true });

  const archivePath = path.join(repoRoot, 'flutter_linux.tar.xz');
  const extractDir = path.join(repoRoot, '.flutter-sdk-extract');
  fs.rmSync(archivePath, { force: true });
  fs.rmSync(extractDir, { recursive: true, force: true });
  fs.mkdirSync(extractDir, { recursive: true });
  run(`curl -L --retry 3 --fail "${archiveInfo.url}" -o "${archivePath}"`);
  extractArchive(archivePath, extractDir, archiveInfo.url);

  const extractedFlutterDir = path.join(extractDir, archiveInfo.extractFolder);
  if (!fs.existsSync(extractedFlutterDir)) {
    throw new Error(`Flutter release archive did not contain expected folder: ${extractedFlutterDir}`);
  }

  fs.renameSync(extractedFlutterDir, flutterDir);
  fs.rmSync(archivePath, { force: true });
  fs.rmSync(extractDir, { recursive: true, force: true });

  if (!fs.existsSync(path.join(flutterBin, 'flutter'))) {
    throw new Error('Flutter release archive did not produce a usable SDK at .flutter-sdk');
  }

  // Stamp the installed version so a future version bump invalidates the cache.
  fs.writeFileSync(flutterStampFile, flutterArchiveVersion);
}

installFlutter();

// Make the freshly-installed Flutter SDK available to every command below.
process.env.PATH = `${flutterBin}${path.delimiter}${process.env.PATH}`;
process.env.CI = 'true';
process.env.FLUTTER_SUPPRESS_ANALYTICS = 'true';

run(`git config --global --add safe.directory "${flutterDir}"`);

run('flutter pub get');

// Run the test suite here (not just flutter build) since Vercel is currently
// the only place a full Flutter SDK is actually available end-to-end — no
// working GitHub Actions runner, no Flutter/Dart SDK reachable from most
// sandboxed dev environments. Deliberately non-blocking: a test failure is
// logged clearly but does not fail the deploy, so this adds a real
// verification signal without introducing a new way to block production
// releases. Revisit this trade-off if/once GitHub Actions is reliable again.
//
// Off by default: the suite (and its very long failure logs) pushed builds
// past Vercel's 45-minute limit (BUILD_EXCEEDED_MAXIMUM_TIME), so production
// never updated. Set VERCEL_RUN_TESTS=1 on the project to turn it back on.
if (process.env.VERCEL_RUN_TESTS === '1') {
  try {
    run('flutter test --reporter compact', { timeout: 10 * 60 * 1000 });
    console.log('flutter test: ALL TESTS PASSED');
  } catch (err) {
    console.log('flutter test: ONE OR MORE TESTS FAILED (see output above) — continuing the build anyway, this step is non-blocking by design.');
  }
} else {
  console.log('flutter test: skipped (set VERCEL_RUN_TESTS=1 to run it here).');
}

// Stamp the commit into the build so error-log entries say which version of
// the app produced them (read via String.fromEnvironment('APP_BUILD')).
const appBuild = (process.env.VERCEL_GIT_COMMIT_SHA || 'local')
  .slice(0, 7)
  .replace(/[^A-Za-z0-9]/g, '');
run(`flutter build web --release --dart-define=APP_BUILD=${appBuild}`);

const index = path.join(repoRoot, 'build', 'web', 'index.html');
if (!fs.existsSync(index)) {
  console.error('Flutter web build did not produce build/web/index.html — failing the deploy.');
  process.exit(1);
}

const versionInfo = JSON.parse(
  fs.readFileSync(path.join(repoRoot, 'build', 'web', 'version.json'), 'utf8'),
);
console.log(
  `Flutter web build complete — version ${versionInfo.version}, build ${versionInfo.build_number}.`,
);
