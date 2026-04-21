import SwiftUI

struct ContentView: View {
    @AppStorage("ssh_hostname") private var hostname = ""
    @AppStorage("ssh_port") private var port = "22"
    @AppStorage("ssh_username") private var username = ""
    @State private var password = ""
    @State private var isConnected = false
    @State private var savePassword = true

    var body: some View {
        NavigationStack {
            if isConnected, let info = makeConnectionInfo() {
                TerminalRepresentable(connectionInfo: info)
                    .ignoresSafeArea(.keyboard)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Disconnect") {
                                isConnected = false
                            }
                        }
                    }
            } else {
                Form {
                    Section("Server") {
                        TextField("Hostname / IP", text: $hostname)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    }
                    Section("Authentication") {
                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        SecureField("Password", text: $password)
                        Toggle("Remember Password", isOn: $savePassword)
                    }
                    Section {
                        Button(action: connect) {
                            HStack {
                                Spacer()
                                Text("Connect")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(hostname.isEmpty || username.isEmpty)
                    }
                }
                .navigationTitle("AWS Terminal")
                .onAppear {
                    if password.isEmpty {
                        password = KeychainManager.load(account: "ssh_password") ?? ""
                    }
                }
            }
        }
    }

    private func makeConnectionInfo() -> SSHConnectionInfo? {
        guard !hostname.isEmpty, !username.isEmpty,
              let p = Int(port) else { return nil }
        return SSHConnectionInfo(
            host: hostname, port: p,
            username: username, password: password,
            privateKey: nil)
    }

    private func connect() {
        if savePassword {
            KeychainManager.save(account: "ssh_password", data: password)
        } else {
            KeychainManager.delete(account: "ssh_password")
        }
        isConnected = true
    }
}

#Preview {
    ContentView()
}
