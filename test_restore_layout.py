import shutil
import tempfile
import unittest
from pathlib import Path

from restore_layout import has_restorable_data, resolve_backup_layout


class ResolveBackupLayoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = Path(tempfile.mkdtemp(prefix="cursor-backup-test-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_nested_appdata_and_dot_cursor(self) -> None:
        roaming = self.tmpdir / "AppData" / "Roaming" / "Cursor" / "User"
        roaming.mkdir(parents=True)
        (roaming / "settings.json").write_text("{}", encoding="utf-8")
        (roaming / "globalStorage").mkdir()
        (roaming / "globalStorage" / "state.vscdb").write_bytes(b"db")

        dot = self.tmpdir / ".cursor"
        dot.mkdir()
        (dot / "argv.json").write_text("{}", encoding="utf-8")
        (dot / "mcp.json").write_text("{}", encoding="utf-8")

        layout = resolve_backup_layout(self.tmpdir)
        self.assertTrue(layout["roaming_cursor"].endswith("AppData/Roaming/Cursor"))
        self.assertTrue(layout["dot_cursor"].endswith(".cursor"))
        self.assertTrue(has_restorable_data(layout))

    def test_users_xp_full_profile_copy(self) -> None:
        roaming = self.tmpdir / "Users" / "Xp" / "AppData" / "Roaming" / "Cursor" / "User"
        roaming.mkdir(parents=True)
        (roaming / "globalStorage").mkdir()
        (self.tmpdir / "Users" / "Xp" / ".cursor").mkdir(parents=True)
        (self.tmpdir / "Users" / "Xp" / ".cursor" / "extensions").mkdir()

        layout = resolve_backup_layout(self.tmpdir)
        self.assertIn("Users/Xp/AppData/Roaming/Cursor", layout["roaming_cursor"].replace("\\", "/"))
        self.assertIn("Users/Xp/.cursor", layout["dot_cursor"].replace("\\", "/"))

    def test_cursor_folder_at_backup_root(self) -> None:
        user = self.tmpdir / "Cursor" / "User"
        user.mkdir(parents=True)
        (user / "keybindings.json").write_text("[]", encoding="utf-8")

        layout = resolve_backup_layout(self.tmpdir)
        self.assertTrue(layout["roaming_cursor"].endswith("Cursor"))

    def test_loose_settings_only(self) -> None:
        (self.tmpdir / "settings.json").write_text("{}", encoding="utf-8")
        (self.tmpdir / "keybindings.json").write_text("[]", encoding="utf-8")
        (self.tmpdir / "snippets").mkdir()

        layout = resolve_backup_layout(self.tmpdir)
        self.assertTrue(layout["loose_settings"].endswith("settings.json"))
        self.assertTrue(layout["loose_keybinds"].endswith("keybindings.json"))
        self.assertTrue(layout["loose_snippets"].endswith("snippets"))
        self.assertTrue(has_restorable_data(layout))

    def test_empty_project_is_not_restorable(self) -> None:
        (self.tmpdir / "README.md").write_text("# gpt\n", encoding="utf-8")
        (self.tmpdir / "src").mkdir()
        layout = resolve_backup_layout(self.tmpdir)
        self.assertFalse(has_restorable_data(layout))

    def test_deep_user_folder_is_found(self) -> None:
        user = self.tmpdir / "old-pc" / "copy" / "Cursor" / "User"
        user.mkdir(parents=True)
        (user / "settings.json").write_text("{}", encoding="utf-8")

        layout = resolve_backup_layout(self.tmpdir)
        self.assertIsNotNone(layout["roaming_cursor"])
        self.assertTrue(layout["roaming_cursor"].endswith("Cursor"))


if __name__ == "__main__":
    unittest.main()
