#include "isxdl\isxdl.iss"

[CustomMessages]
DependenciesDir=MyProgramDependencies

en.depdownload_msg=The following applications are required before setup can continue:%n%n%1%nDownload and install now?
de.depdownload_msg=Die folgenden Programme werden benötigt bevor das Setup fortfahren kann:%n%n%1%nJetzt downloaden und installieren?

en.depdownload_memo_title=Download dependencies
de.depdownload_memo_title=Abhängigkeiten downloaden

en.depinstall_memo_title=Install dependencies
de.depinstall_memo_title=Abhängigkeiten installieren

en.depinstall_title=Installing dependencies
de.depinstall_title=Installiere Abhängigkeiten

en.depinstall_description=Please wait while Setup installs dependencies on your computer.
de.depinstall_description=Warten Sie bitte während Abhängigkeiten auf Ihrem Computer installiert wird.

en.depinstall_status=Installing %1...
de.depinstall_status=Installiere %1...

en.depinstall_missing=%1 must be installed before setup can continue. Please install %1 and run Setup again.
de.depinstall_missing=%1 muss installiert werden bevor das Setup fortfahren kann. Bitte installieren Sie %1 und starten Sie das Setup erneut.

en.depinstall_error=An error occured while installing the dependencies. Please restart the computer and run the setup again or install the following dependencies manually:%n
de.depinstall_error=Ein Fehler ist während der Installation der Abghängigkeiten aufgetreten. Bitte starten Sie den Computer neu und führen Sie das Setup erneut aus oder installieren Sie die folgenden Abhängigkeiten per Hand:%n

en.isxdl_langfile=
de.isxdl_langfile=german.ini

[Files]
Source: "scripts\isxdl\german.ini"; Flags: dontcopy

[Code]
type
	TProduct = record
		File: String;
		Title: String;
		Parameters: String;
		ForceSuccess : boolean;
		InstallClean : boolean;
		MustRebootAfter : boolean;
	end;

	InstallResult = (InstallSuccessful, InstallRebootRequired, InstallError);

var
	installMemo, downloadMemo, downloadMessage: string;
	products: array of TProduct;
	delayedReboot, isForcedX86: boolean;
	DependencyPage: TOutputProgressWizardPage;


procedure AddProduct(filename, parameters, title, size, url: string; forceSuccess, installClean, mustRebootAfter : boolean);
var
	path: string;
	i: Integer;
begin
	installMemo := installMemo + '%1' + title + #13;

	path := ExpandConstant('{src}{\}') + CustomMessage('DependenciesDir') + '\' + filename;
	if not FileExists(path) then begin
		path := ExpandConstant('{tmp}{\}') + filename;

		if not FileExists(path) then begin
			isxdl_AddFile(url, path);

			downloadMemo := downloadMemo + '%1' + title + #13;
			downloadMessage := downloadMessage + '	' + title + ' (' + size + ')' + #13;
		end;
	end;

	i := GetArrayLength(products);
	SetArrayLength(products, i + 1);
	products[i].File := path;
	products[i].Title := title;
	products[i].Parameters := parameters;
	products[i].ForceSuccess := forceSuccess;
	products[i].InstallClean := installClean;
	products[i].MustRebootAfter := mustRebootAfter;
end;

function SmartExec(product : TProduct; var resultcode : Integer): boolean;
begin
	if (LowerCase(Copy(product.File, Length(product.File) - 2, 3)) = 'exe') then begin
		Result := Exec(product.File, product.Parameters, '', SW_SHOWNORMAL, ewWaitUntilTerminated, resultcode);
	end else begin
		Result := ShellExec('', product.File, product.Parameters, '', SW_SHOWNORMAL, ewWaitUntilTerminated, resultcode);
	end;
end;

function PendingReboot: boolean;
var	names: String;
begin
	if (RegQueryMultiStringValue(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Control\Session Manager', 'PendingFileRenameOperations', names)) then begin
		Result := true;
	end else if ((RegQueryMultiStringValue(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Control\Session Manager', 'SetupExecute', names)) and (names <> ''))  then begin
		Result := true;
	end else begin
		Result := false;
	end;
end;

function InstallProducts: InstallResult;
var
	resultCode, i, productCount, finishCount: Integer;
begin
	Result := InstallSuccessful;
	productCount := GetArrayLength(products);

	if productCount > 0 then begin
		DependencyPage := CreateOutputProgressPage(CustomMessage('depinstall_title'), CustomMessage('depinstall_description'));
		DependencyPage.Show;

		for i := 0 to productCount - 1 do begin
			if (products[i].InstallClean and (delayedReboot or PendingReboot())) then begin
				Result := InstallRebootRequired;
				break;
			end;

			DependencyPage.SetText(FmtMessage(CustomMessage('depinstall_status'), [products[i].Title]), '');
			DependencyPage.SetProgress(i, productCount);

			if SmartExec(products[i], resultCode) then begin
				//setup executed; resultCode contains the exit code
				if (products[i].MustRebootAfter) then begin
					//delay reboot after install if we installed the last dependency anyways
					if (i = productCount - 1) then begin
						delayedReboot := true;
					end else begin
						Result := InstallRebootRequired;
					end;
					break;
				end else if (resultCode = 0) or (products[i].ForceSuccess) then begin
					finishCount := finishCount + 1;
				end else if (resultCode = 3010) then begin
					//Windows Installer resultCode 3010: ERROR_SUCCESS_REBOOT_REQUIRED
					delayedReboot := true;
					finishCount := finishCount + 1;
				end else begin
					Result := InstallError;
					break;
				end;
			end else begin
				Result := InstallError;
				break;
			end;
		end;

		//only leave not installed products for error message
		for i := 0 to productCount - finishCount - 1 do begin
			products[i] := products[i+finishCount];
		end;
		SetArrayLength(products, productCount - finishCount);

		DependencyPage.Hide;
	end;
end;

function PrepareToInstall(var NeedsRestart: boolean): String;
var
	i: Integer;
	s: string;
begin
	delayedReboot := false;

	case InstallProducts() of
		InstallError: begin
			s := CustomMessage('depinstall_error');

			for i := 0 to GetArrayLength(products) - 1 do begin
				s := s + #13 + '	' + products[i].Title;
			end;

			Result := s;
			end;
		InstallRebootRequired: begin
			Result := products[0].Title;
			NeedsRestart := true;

			//write into the registry that the installer needs to be executed again after restart
			RegWriteStringValue(HKEY_CURRENT_USER, 'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'InstallBootstrap', ExpandConstant('{srcexe}'));
			end;
	end;
end;

function NeedRestart : boolean;
begin
	Result := delayedReboot;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
	s: string;
begin
	if downloadMemo <> '' then
		s := s + CustomMessage('depdownload_memo_title') + ':' + NewLine + FmtMessage(downloadMemo, [Space]) + NewLine;
	if installMemo <> '' then
		s := s + CustomMessage('depinstall_memo_title') + ':' + NewLine + FmtMessage(installMemo, [Space]) + NewLine;

	s := s + MemoDirInfo + NewLine + NewLine + MemoGroupInfo

	if MemoTasksInfo <> '' then
		s := s + NewLine + NewLine + MemoTasksInfo;

	Result := s
end;

function NextButtonClick(CurPageID: Integer): boolean;
begin
	Result := true;

	if CurPageID = wpReady then begin
		if downloadMemo <> '' then begin
			//change isxdl language only if it is not english because isxdl default language is already english
			if (ActiveLanguage() <> 'en') then begin
				ExtractTemporaryFile(CustomMessage('isxdl_langfile'));
				isxdl_SetOption('language', ExpandConstant('{tmp}{\}') + CustomMessage('isxdl_langfile'));
			end;
			//isxdl_SetOption('title', FmtMessage(SetupMessage(msgSetupWindowTitle), [CustomMessage('appname')]));

			if SuppressibleMsgBox(FmtMessage(CustomMessage('depdownload_msg'), [downloadMessage]), mbConfirmation, MB_YESNO, IDYES) = IDNO then
				Result := false
			else if isxdl_DownloadFiles(StrToInt(ExpandConstant('{wizardhwnd}'))) = 0 then
				Result := false;
		end;
	end;
end;

function IsX86: boolean;
begin
	Result := isForcedX86 or (ProcessorArchitecture = paX86) or (ProcessorArchitecture = paUnknown);
end;

function IsX64: boolean;
begin
	Result := (not isForcedX86) and Is64BitInstallMode and (ProcessorArchitecture = paX64);
end;

function IsIA64: boolean;
begin
	Result := (not isForcedX86) and Is64BitInstallMode and (ProcessorArchitecture = paIA64);
end;

function GetString(x86, x64, ia64: String): String;
begin
	if IsX64() and (x64 <> '') then begin
		Result := x64;
	end else if IsIA64() and (ia64 <> '') then begin
		Result := ia64;
	end else begin
		Result := x86;
	end;
end;

function GetArchitectureString(): String;
begin
	if IsX64() then begin
		Result := '_x64';
	end else if IsIA64() then begin
		Result := '_ia64';
	end else begin
		Result := '';
	end;
end;

procedure SetForceX86(value: boolean);
begin
	isForcedX86 := value;
end;

[Setup]
