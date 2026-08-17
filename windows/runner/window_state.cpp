#include "window_state.h"

#include <algorithm>

namespace {

constexpr wchar_t kRegistryPath[] =
    L"Software\\Langbai\\ImageScrambler\\Window";

bool ReadDword(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD size = sizeof(DWORD);
  return RegGetValue(key, nullptr, name, RRF_RT_REG_DWORD, nullptr, value,
                     &size) == ERROR_SUCCESS;
}

void WriteDword(HKEY key, const wchar_t* name, int value) {
  const DWORD data = static_cast<DWORD>(value);
  RegSetValueEx(key, name, 0, REG_DWORD,
                reinterpret_cast<const BYTE*>(&data), sizeof(data));
}

bool IsVisibleOnAnyMonitor(const SavedWindowState& state) {
  RECT rect{state.x, state.y, state.x + state.width, state.y + state.height};
  return MonitorFromRect(&rect, MONITOR_DEFAULTTONULL) != nullptr;
}

}  // namespace

SavedWindowState LoadWindowState() {
  SavedWindowState state;
  HKEY key = nullptr;
  if (RegOpenKeyEx(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return state;
  }
  DWORD x = 0;
  DWORD y = 0;
  DWORD width = 0;
  DWORD height = 0;
  const bool complete = ReadDword(key, L"X", &x) &&
                        ReadDword(key, L"Y", &y) &&
                        ReadDword(key, L"Width", &width) &&
                        ReadDword(key, L"Height", &height);
  RegCloseKey(key);
  if (!complete) return state;

  state.x = static_cast<int>(x);
  state.y = static_cast<int>(y);
  state.width = static_cast<int>(width);
  state.height = static_cast<int>(height);
  if (state.width < 900 || state.height < 620 || state.width > 10000 ||
      state.height > 10000 || !IsVisibleOnAnyMonitor(state)) {
    return SavedWindowState{};
  }
  state.restored = true;
  return state;
}

void SaveWindowState(HWND window) {
  if (window == nullptr || IsIconic(window)) return;
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window, &placement)) return;
  const RECT rect = placement.rcNormalPosition;
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width < 900 || height < 620) return;

  HKEY key = nullptr;
  if (RegCreateKeyEx(HKEY_CURRENT_USER, kRegistryPath, 0, nullptr, 0,
                     KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  WriteDword(key, L"X", rect.left);
  WriteDword(key, L"Y", rect.top);
  WriteDword(key, L"Width", width);
  WriteDword(key, L"Height", height);
  RegCloseKey(key);
}
