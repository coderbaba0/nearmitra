package ui

import (
	"strings"
	"testing"
)

func TestFolderPickerUsesOwnerAndLiteralInitialDirectory(t *testing.T) {
	script := folderPickerScript(123456, `C:\Users\O'Brien\नया $(Write-Output wrong)`)
	for _, want := range []string{
		"$owner.AssignHandle([IntPtr]123456)",
		"$f.ShowDialog($owner)",
		"$f.SelectedPath = 'C:\\Users\\O''Brien\\नया $(Write-Output wrong)'",
		"$f.ShowNewFolderButton = $true",
		"$f.Dispose(); $owner.ReleaseHandle()",
		"System.Text.UTF8Encoding($false)",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("folder picker missing %q", want)
		}
	}
}
