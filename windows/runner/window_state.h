#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>

struct SavedWindowState {
  int x = 10;
  int y = 10;
  int width = 1302;
  int height = 842;
  bool restored = false;
};

SavedWindowState LoadWindowState();
void SaveWindowState(HWND window);

#endif  // RUNNER_WINDOW_STATE_H_
