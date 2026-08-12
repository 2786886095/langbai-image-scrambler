#include <windows.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace {

std::wstring Quote(const std::wstring& value) {
  std::wstring quoted = L"\"";
  size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      backslashes++;
      continue;
    }
    if (character == L'\"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(L'\"');
      backslashes = 0;
      continue;
    }
    quoted.append(backslashes, L'\\');
    backslashes = 0;
    quoted.push_back(character);
  }
  quoted.append(backslashes * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

std::wstring Timestamp() {
  SYSTEMTIME time;
  GetLocalTime(&time);
  wchar_t buffer[64];
  swprintf_s(buffer, L"%04u-%02u-%02u %02u:%02u:%02u.%03u", time.wYear,
             time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
             time.wMilliseconds);
  return buffer;
}

void Log(const std::filesystem::path& log_path, const std::wstring& message) {
  std::ofstream stream(log_path, std::ios::app | std::ios::binary);
  if (stream) {
    const std::wstring line = L"[" + Timestamp() + L"] " + message + L"\r\n";
    const int byte_count = WideCharToMultiByte(
        CP_UTF8, 0, line.c_str(), static_cast<int>(line.size()), nullptr, 0,
        nullptr, nullptr);
    std::string utf8(byte_count, '\0');
    WideCharToMultiByte(CP_UTF8, 0, line.c_str(),
                        static_cast<int>(line.size()), utf8.data(), byte_count,
                        nullptr, nullptr);
    stream.write(utf8.data(), utf8.size());
  }
}

bool WaitForApp(DWORD process_id, const std::filesystem::path& log_path) {
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, process_id);
  if (process == nullptr) {
    const DWORD error = GetLastError();
    if (error == ERROR_INVALID_PARAMETER) {
      Log(log_path, L"Application process already exited.");
      return true;
    }
    Log(log_path, L"OpenProcess failed: " + std::to_wstring(error));
    return false;
  }
  const DWORD result = WaitForSingleObject(process, 120000);
  CloseHandle(process);
  if (result != WAIT_OBJECT_0) {
    Log(log_path, L"Timed out waiting for application exit: " +
                      std::to_wstring(result));
    return false;
  }
  Log(log_path, L"Application process exited.");
  return true;
}

bool RunInstaller(const std::filesystem::path& installer,
                  const std::filesystem::path& install_directory,
                  const std::filesystem::path& log_path) {
  const std::filesystem::path installer_log =
      log_path.parent_path() / L"installer.log";
  const std::wstring parameters =
      L"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS "
      L"/RESTARTAPPLICATIONS /LOG=" +
      Quote(installer_log.wstring()) + L" /DIR=" +
      Quote(install_directory.wstring());
  Log(log_path, L"Starting installer: " + installer.wstring());
  const std::filesystem::path installer_directory = installer.parent_path();

  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  info.lpVerb = L"open";
  info.lpFile = installer.c_str();
  info.lpParameters = parameters.c_str();
  info.lpDirectory = installer_directory.c_str();
  info.nShow = SW_HIDE;
  if (!ShellExecuteExW(&info) || info.hProcess == nullptr) {
    Log(log_path, L"ShellExecuteEx failed: " +
                      std::to_wstring(GetLastError()));
    return false;
  }
  const DWORD wait_result = WaitForSingleObject(info.hProcess, 300000);
  DWORD exit_code = ERROR_INSTALL_FAILURE;
  GetExitCodeProcess(info.hProcess, &exit_code);
  CloseHandle(info.hProcess);
  Log(log_path, L"Installer finished: wait=" + std::to_wstring(wait_result) +
                    L", exit=" + std::to_wstring(exit_code));
  return wait_result == WAIT_OBJECT_0 && exit_code == 0;
}

bool RestartApplication(const std::filesystem::path& executable,
                        const std::filesystem::path& working_directory,
                        const std::filesystem::path& log_path) {
  if (!std::filesystem::exists(executable)) {
    Log(log_path, L"Updated application not found: " + executable.wstring());
    return false;
  }
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_FLAG_NO_UI;
  info.lpVerb = L"open";
  info.lpFile = executable.c_str();
  info.lpDirectory = working_directory.c_str();
  info.nShow = SW_SHOWNORMAL;
  const bool started = ShellExecuteExW(&info) == TRUE;
  if (started) {
    Log(log_path, L"Updated application restarted.");
  } else {
    Log(log_path,
        L"Application restart failed: " + std::to_wstring(GetLastError()));
  }
  return started;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE previous,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  int argument_count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr || argument_count != 7) {
    if (arguments != nullptr) LocalFree(arguments);
    return ERROR_BAD_ARGUMENTS;
  }

  const std::filesystem::path installer = arguments[1];
  const DWORD application_pid = wcstoul(arguments[2], nullptr, 10);
  const std::filesystem::path install_directory = arguments[3];
  const std::filesystem::path application_executable = arguments[4];
  const std::filesystem::path log_path = arguments[5];
  const std::filesystem::path ready_path = arguments[6];
  LocalFree(arguments);

  Log(log_path, L"Update helper started.");
  if (!std::filesystem::exists(installer)) {
    Log(log_path, L"Installer not found: " + installer.wstring());
    return ERROR_FILE_NOT_FOUND;
  }
  {
    std::ofstream ready(ready_path, std::ios::trunc);
    if (!ready) {
      Log(log_path, L"Could not create readiness marker: " +
                        ready_path.wstring());
      return ERROR_WRITE_FAULT;
    }
    ready << "ready\n";
  }
  if (!WaitForApp(application_pid, log_path)) return ERROR_TIMEOUT;
  if (!RunInstaller(installer, install_directory, log_path)) {
    RestartApplication(application_executable, install_directory, log_path);
    return ERROR_INSTALL_FAILURE;
  }
  if (!RestartApplication(application_executable, install_directory, log_path)) {
    return ERROR_FILE_NOT_FOUND;
  }

  std::error_code ignored;
  std::filesystem::remove(installer, ignored);
  std::filesystem::remove(ready_path, ignored);
  wchar_t helper_path[MAX_PATH];
  if (GetModuleFileNameW(nullptr, helper_path, MAX_PATH) > 0) {
    MoveFileExW(helper_path, nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
    MoveFileExW(installer.parent_path().c_str(), nullptr,
                MOVEFILE_DELAY_UNTIL_REBOOT);
  }
  return 0;
}
