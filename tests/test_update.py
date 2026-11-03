import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("update", ROOT / "scripts/update.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def release(version="99.0.0-beta"):
    return {
        "tagName": f"v{version}", "isDraft": False, "isPrerelease": "-nightly-" in version,
        "assets": [{
            "name": f"opentubex-{version}-win-{arch}-portable.zip",
            "url": f"https://github.com/OpenTubeX/OpenTubeX/releases/download/v{version}/opentubex-{version}-win-{arch}-portable.zip",
            "state": "uploaded", "digest": f"sha256:{digest * 64}",
        } for arch, digest in (("x64", "a"), ("arm64", "b"))],
    }


def manifest(name):
    return json.loads((ROOT / "bucket" / name).read_text())


class StableUpdateTests(unittest.TestCase):
    def setUp(self):
        self.manifest = manifest("opentubex.json")

    def test_updates_version_and_both_architectures(self):
        result = updater.update(self.manifest, release())
        self.assertEqual(result["version"], "99.0.0-beta")
        self.assertEqual(result["architecture"]["64bit"], {
            "url": "https://github.com/OpenTubeX/OpenTubeX/releases/download/v99.0.0-beta/opentubex-99.0.0-beta-win-x64-portable.zip",
            "hash": "a" * 64,
        })
        self.assertEqual(result["architecture"]["arm64"]["hash"], "b" * 64)
        self.assertEqual(result["persist"], "OpenTubeX-data")
        self.assertEqual(updater.update(result, release()), result)

    def test_rejects_unpublished_and_nightly_releases(self):
        for field in ("isDraft", "isPrerelease"):
            data = release()
            data[field] = True
            with self.subTest(field=field), self.assertRaises(ValueError):
                updater.update(self.manifest, data)
        with self.assertRaises(ValueError):
            updater.update(self.manifest, release("99.0.0-nightly-123"))
        data = release("99.0.0-nightly-123")
        data["isPrerelease"] = False
        with self.assertRaises(ValueError):
            updater.update(self.manifest, data, nightly=True)

    def test_rejects_downgrade(self):
        with self.assertRaisesRegex(ValueError, "downgrade"):
            updater.update(self.manifest, release("0.0.1-beta"))

    def test_accepts_final_release_after_beta(self):
        beta = updater.update(self.manifest, release())
        final = updater.update(beta, release("99.0.0"))
        self.assertEqual(final["version"], "99.0.0")
        with self.assertRaisesRegex(ValueError, "downgrade"):
            updater.update(final, release())

    def test_requires_both_unique_assets(self):
        for assets in (release()["assets"][:1], release()["assets"] * 2):
            data = release()
            data["assets"] = assets
            with self.assertRaises(ValueError):
                updater.update(self.manifest, data)

    def test_rejects_bad_asset_metadata(self):
        for field, value in (("digest", None), ("digest", "sha256:bad"),
                             ("state", "new"), ("url", "https://example.com/app.zip")):
            for index in (0, 1):
                data = copy.deepcopy(release())
                data["assets"][index][field] = value
                with self.subTest(field=field, index=index), self.assertRaises(ValueError):
                    updater.update(self.manifest, data)

    def test_rejects_changed_manifest_structure(self):
        del self.manifest["architecture"]["arm64"]
        with self.assertRaises(ValueError):
            updater.update(self.manifest, release())


class NightlyUpdateTests(unittest.TestCase):
    def setUp(self):
        self.manifest = manifest("opentubex-nightly.json")

    def update(self, version, source=None):
        return updater.update(source or self.manifest, release(version), nightly=True)

    def test_follows_nightly_and_stable_releases(self):
        result = self.update("99.0.0-nightly-123")
        self.assertEqual(result["version"], "99.0.0-nightly-123")
        self.assertEqual(result["architecture"]["64bit"]["hash"], "a" * 64)
        self.assertEqual(result["architecture"]["arm64"]["hash"], "b" * 64)
        self.assertEqual(self.update("99.0.1-beta", result)["version"], "99.0.1-beta")

    def test_keeps_newer_build(self):
        result = self.update("99.0.0-nightly-123")
        for version in ("99.0.0-beta", "99.0.0-nightly-122", "98.9.9-nightly-999"):
            with self.subTest(version=version):
                self.assertEqual(self.update(version, result), result)
        self.assertEqual(self.update("99.0.0-nightly-124", result)["version"], "99.0.0-nightly-124")


if __name__ == "__main__":
    unittest.main()
