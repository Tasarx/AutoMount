import SwiftUI

struct ContentView: View {
    @State private var existingMounts: [AutoNasEntry] = []
    @State private var isFetching: Bool = false
    @State private var fetchError: String? = nil
    @State private var selectedMount: AutoNasEntry? = nil

    // Form inputs
    @State private var serverDisplayName: String = ""
    @State private var ipAddress: String = ""
    @State private var smbShareName: String = ""
    @State private var username: String = ""
    @State private var password: String = ""

    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isWorking: Bool = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedMount) {
                if isFetching {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }.padding(.vertical, 8)
                } else if let error = fetchError {
                    Text(error).font(.caption).foregroundColor(.red)
                } else if existingMounts.isEmpty {
                    Text("No mounts configured.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
                
                ForEach(existingMounts) { mount in
                    NavigationLink(value: mount) {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(mount.serverName)
                                    .fontWeight(.medium)
                                Text(mount.ipAddress)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive, action: { remove(mount: mount) }) {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("NAS Mounts")
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refreshMounts) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isFetching)
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { selectedMount = nil }) {
                        Label("Add New", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let mount = selectedMount {
                mountDetailView(for: mount)
            } else {
                newMountForm()
            }
        }
        .task {
            refreshMounts()
        }
    }

    // MARK: - Handlers

    private func refreshMounts() {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let mounts = try AutomountManager.fetchExistingMounts()
                DispatchQueue.main.async {
                    self.existingMounts = mounts
                    self.isFetching = false
                    
                    // If the currently selected mount was deleted externally, clear selection
                    if let selection = self.selectedMount, !mounts.contains(selection) {
                        self.selectedMount = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.fetchError = error.localizedDescription
                    self.isFetching = false
                }
            }
        }
    }

    private func remove(mount: AutoNasEntry) {
        guard !isWorking else { return }
        isWorking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AutomountManager.removeMount(path: mount.id)
                DispatchQueue.main.async {
                    if self.selectedMount == mount {
                        self.selectedMount = nil
                    }
                    self.isWorking = false
                    self.refreshMounts()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    // Optional: show error alert to user
                }
            }
        }
    }

    private func setupNewMount() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Authenticating and configuring mounts..."
        isError = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AutomountManager.setupAutofs(
                    serverName: serverDisplayName,
                    ipAddress: ipAddress,
                    shareName: smbShareName,
                    username: username,
                    password: password
                )
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.isError = false
                    self.statusMessage = "Mount successfully created!"
                    
                    // Clear fields safely
                    self.serverDisplayName = ""
                    self.ipAddress = ""
                    self.smbShareName = ""
                    self.username = ""
                    self.password = ""
                    
                    self.refreshMounts()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.isError = true
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func mountDetailView(for mount: AutoNasEntry) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "network")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
            
            Text(mount.serverName)
                .font(.largeTitle.bold())
            
            Form {
                Section("Configuration Details") {
                    LabeledContent("IP Address", value: mount.ipAddress)
                    LabeledContent("SMB Share", value: mount.shareName)
                    LabeledContent("Username", value: mount.username)
                    LabeledContent("Target Path") {
                        Text(mount.id)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 500, maxHeight: 220)
            
            Button(role: .destructive, action: { remove(mount: mount) }) {
                if isWorking {
                    ProgressView().controlSize(.small).padding(.horizontal)
                } else {
                    Text("Disconnect & Remove")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
            .frame(width: 300)
            
            Spacer()
        }
        .navigationTitle(mount.serverName)
        // Adjust style slightly so it looks neat across the window pane
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func newMountForm() -> some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Rectangle()
                    .fill(Color.blue.gradient)
                    .frame(height: 100)
                
                VStack {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white)
                    Text("New Mount")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                }
            }
            .edgesIgnoringSafeArea(.top)

            Form {
                Section(header: Text("Server Details")) {
                    TextField("Display Name (e.g., TrueNAS)", text: $serverDisplayName)
                        .textFieldStyle(.roundedBorder)
                    TextField("IP Address", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                    TextField("SMB Share Name", text: $smbShareName)
                        .textFieldStyle(.roundedBorder)
                }

                Section(header: Text("Credentials")) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .disableAutocorrection(true)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            // Status message area
            if !statusMessage.isEmpty {
                HStack {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(statusMessage)
                }
                .font(.footnote)
                .foregroundColor(isError ? .red : .green)
                .padding(.horizontal)
                .padding(.top, 8)
                .animation(.easeInOut, value: statusMessage)
            }

            // Footer
            VStack {
                Button(action: setupNewMount) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 24)
                    } else {
                        Text("Create Persistent Mount")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(serverDisplayName.isEmpty || ipAddress.isEmpty || smbShareName.isEmpty || username.isEmpty || password.isEmpty || isWorking)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
                .padding(.top, 16)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("Add Mount")
    }
}

#Preview {
    ContentView()
}
