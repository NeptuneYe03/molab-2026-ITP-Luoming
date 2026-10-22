import SwiftUI
import Observation
import PhotosUI
import UIKit
import AVFoundation

// MARK: - 分类
enum CraftCategory: String, CaseIterable, Identifiable, Codable {
    case sewing
    case electronics
    case decorations
    case drawing
    case tools
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sewing: "Sewing"
        case .electronics: "Electronics"
        case .decorations: "Decorations"
        case .drawing: "Art Supplies"
        case .tools: "Tools & Hardware"
        case .other: "Other Treasures"
        }
    }

    var subtitle: String {
        switch self {
        case .sewing: "Fabric, thread & ribbons"
        case .electronics: "Motors, LEDs & circuits"
        case .decorations: "Beads, bows & stickers"
        case .drawing: "Pens, paint & paper"
        case .tools: "Screws, pliers & rulers"
        case .other: "A little bit of everything"
        }
    }

    var emoji: String {
        switch self {
        case .sewing: "🧵"
        case .electronics: "🤖"
        case .decorations: "🎀"
        case .drawing: "🎨"
        case .tools: "🛠️"
        case .other: "📦"
        }
    }

    var color: Color {
        switch self {
        case .sewing:
            Color(red: 0.80, green: 0.74, blue: 0.98)
        case .electronics:
            Color(red: 0.56, green: 0.76, blue: 1.00)
        case .decorations:
            Color(red: 1.00, green: 0.85, blue: 0.38)
        case .drawing:
            Color(red: 1.00, green: 0.72, blue: 0.72)
        case .tools:
            Color(red: 0.64, green: 0.86, blue: 0.76)
        case .other:
            Color(red: 0.75, green: 0.81, blue: 0.92)
        }
    }
}

// MARK: - 配色
enum CabinetTheme {
    static let background = Color(
        red: 0.91, green: 0.95, blue: 1.00
    )

    static let ink = Color(
        red: 0.13, green: 0.20, blue: 0.39
    )

    static let yellow = Color(
        red: 1.00, green: 0.88, blue: 0.43
    )
}

// MARK: - 一件物品的数据
// Codable 让物品可以转换成 JSON，也可以从 JSON 还原。
struct CraftItem: Identifiable, Codable {
    var id = UUID()
    var name = ""
    var category: CraftCategory = .sewing
    var quantity: Double = 1
    var unit = "pcs"
    var location = ""
    var notes = ""
    // 可选字段：第六周没有照片的 JSON 也能正常读取。
    var photoFilename: String? = nil

    var quantityText: String {
        "\(quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }
}

// MARK: - 数据管理与 JSON 保存
@Observable
final class CabinetStore {
    private(set) var items: [CraftItem] = []
    var loadError: String?

    // 读取失败时阻止覆盖原文件，避免已有记录丢失。
    private var canWrite = true

    init() {
        do {
            let url = try fileURL()

            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                items = try JSONDecoder().decode(
                    [CraftItem].self,
                    from: data
                )
            }
        } catch {
            canWrite = false
            loadError = """
            Your saved items could not be opened. \
            The original file has been kept unchanged.

            \(error.localizedDescription)
            """
        }
    }

    // JSON 保存在当前 App 的 Documents 目录中。
    private func fileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return directory.appendingPathComponent("cabinet.json")
    }

    // 先成功写入文件，再更新界面中的数据。
    private func commit(_ updatedItems: [CraftItem]) throws {
        guard canWrite else {
            throw NSError(
                domain: "CraftCabinet",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Saving is unavailable because the existing data could not be loaded."
                ]
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(updatedItems)
        try data.write(to: fileURL(), options: .atomic)

        items = updatedItems
    }

    // 图片先写入新文件，JSON 保存成功后才删除旧图片。
    func save(
        _ item: CraftItem,
        photoData: Data? = nil,
        removePhoto: Bool = false
    ) throws {
        let oldFilename = self.item(id: item.id)?.photoFilename
        var savedItem = item
        var newFilename: String?

        if let photoData {
            let filename = UUID().uuidString + ".jpg"
            try PhotoStorage.write(photoData, filename: filename)
            newFilename = filename
            savedItem.photoFilename = filename
        } else if removePhoto {
            savedItem.photoFilename = nil
        }

        var updatedItems = items
        if let index = updatedItems.firstIndex(where: { $0.id == item.id }) {
            updatedItems[index] = savedItem
        } else {
            updatedItems.insert(savedItem, at: 0)
        }

        do {
            try commit(updatedItems)
        } catch {
            PhotoStorage.remove(filename: newFilename)
            throw error
        }

        if oldFilename != savedItem.photoFilename {
            PhotoStorage.remove(filename: oldFilename)
        }
    }

    func delete(id: UUID) throws {
        let filename = item(id: id)?.photoFilename
        try commit(items.filter { $0.id != id })
        PhotoStorage.remove(filename: filename)
    }

    func item(id: UUID) -> CraftItem? {
        items.first { $0.id == id }
    }

    func items(in category: CraftCategory) -> [CraftItem] {
        items.filter { $0.category == category }
    }
}

// MARK: - 首页
struct ContentView: View {
    // 整个 App 共用这一份数据。
    @State private var store = CabinetStore()
    @State private var showingAdd = false
    @State private var searchText = ""
    // 控制搜索框是否正在输入。
    @FocusState private var isSearchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var searchResults: [CraftItem] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return store.items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                        .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
                    welcomeCard
                        .onTapGesture { isSearchFocused = false }
                    searchField

                    if searchText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty {
                        categoryGrid
                            .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
                    } else {
                        searchSection
                            .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
                    }

                    Label(
                        "Little supplies, big ideas",
                        systemImage: "sparkles"
                    )
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(
                        CabinetTheme.ink.opacity(0.65)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onTapGesture { isSearchFocused = false }
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            // 滑动页面，或点击背景空白处，收起键盘。
            .scrollDismissesKeyboard(.interactively)
            .background {
                CabinetTheme.background
                    .ignoresSafeArea()
                    .onTapGesture { isSearchFocused = false }
            }
            .foregroundStyle(CabinetTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) {
                ItemEditorView(
                    item: CraftItem(),
                    isNew: true
                )
            }
            .alert(
                "Couldn't Load Items",
                isPresented: Binding(
                    get: { store.loadError != nil },
                    set: {
                        if !$0 {
                            store.loadError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    store.loadError = nil
                }
            } message: {
                Text(store.loadError ?? "")
            }
        }
        .environment(store)
        .tint(CabinetTheme.ink)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Craft Cabinet")
                    .font(.system(
                        size: 29,
                        weight: .heavy,
                        design: .rounded
                    ))

                Text("Your supplies, tucked away.")
                    .font(.subheadline)
                    .foregroundStyle(
                        CabinetTheme.ink.opacity(0.7)
                    )
            }

            Spacer(minLength: 0)

            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .frame(width: 48, height: 48)
                    .background(CabinetTheme.yellow)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 17)
                    )
            }
            .accessibilityLabel("Add Item")
        }
        .padding(.top, 12)
    }

    private var welcomeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ready to\nmake something?")
                    .font(.system(
                        size: 25,
                        weight: .bold,
                        design: .rounded
                    ))

                Text(
                    "\(store.items.count) treasures in your cabinet"
                )
                .font(.subheadline)
            }

            Spacer(minLength: 0)

            Text("🧶")
                .font(.system(size: 56))
                .rotationEffect(.degrees(-12))
                .accessibilityHidden(true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CabinetTheme.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")

            TextField("Find a little treasure...", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    isSearchFocused = false
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(15)
        .background(.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Explore your drawers")
                .font(.system(
                    size: 21,
                    weight: .bold,
                    design: .rounded
                ))

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(CraftCategory.allCases) { category in
                    NavigationLink {
                        CategoryView(category: category)
                    } label: {
                        CategoryCard(
                            category: category,
                            count: store.items(in: category).count
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found treasures")
                .font(.title3.bold())

            if searchResults.isEmpty {
                Text("No matching items yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(searchResults) { item in
                    NavigationLink {
                        ItemDetailView(itemID: item.id)
                    } label: {
                        CraftItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 分类卡片
struct CategoryCard: View {
    let category: CraftCategory
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(category.emoji)
                    .font(.system(size: 36))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.subheadline.bold())
                    .accessibilityHidden(true)
            }

            Text(category.title)
                .font(.system(
                    size: 18,
                    weight: .bold,
                    design: .rounded
                ))
                .fixedSize(horizontal: false, vertical: true)

            Text(category.subtitle)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("\(count) \(count == 1 ? "item" : "items")")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.45))
                .clipShape(Capsule())
        }
        .padding(17)
        .frame(
            maxWidth: .infinity,
            minHeight: 195,
            alignment: .topLeading
        )
        .background(category.color)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .foregroundStyle(CabinetTheme.ink)
    }
}

// MARK: - 分类中的物品列表
struct CategoryView: View {
    @Environment(CabinetStore.self) private var store
    @State private var showingAdd = false

    let category: CraftCategory

    private var categoryItems: [CraftItem] {
        store.items(in: category)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if categoryItems.isEmpty {
                    emptyState
                } else {
                    ForEach(categoryItems) { item in
                        NavigationLink {
                            ItemDetailView(itemID: item.id)
                        } label: {
                            CraftItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(CabinetTheme.background)
        .foregroundStyle(CabinetTheme.ink)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
        .sheet(isPresented: $showingAdd) {
            ItemEditorView(
                item: CraftItem(category: category),
                isNew: true
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text(category.emoji)
                .font(.system(size: 72))
                .frame(width: 145, height: 145)
                .background(category.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: 38)
                )
                .rotationEffect(.degrees(-6))
                .accessibilityHidden(true)

            Text("An empty little drawer")
                .font(.system(
                    size: 24,
                    weight: .bold,
                    design: .rounded
                ))

            Text("Let's give your first treasure a home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingAdd = true
            } label: {
                Label("Add Your First Item", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(CabinetTheme.yellow)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 45)
    }
}

// MARK: - 单条物品卡片
struct CraftItemRow: View {
    let item: CraftItem

    var body: some View {
        HStack(spacing: 14) {
            ItemPhotoView(item: item)
                .frame(width: 62, height: 66)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(item.quantityText)
                    .font(.subheadline)
                    .foregroundStyle(
                        item.quantity == 0
                        ? Color.red
                        : CabinetTheme.ink.opacity(0.7)
                    )

                if !item.location.isEmpty {
                    Label(item.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .foregroundStyle(CabinetTheme.ink)
    }
}

// MARK: - 添加与编辑表单
struct ItemEditorView: View {
    @Environment(CabinetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CraftItem
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var removePhoto = false
    @State private var isLoadingPhoto = false
    @State private var showingCamera = false
    @State private var requestingCamera = false
    @FocusState private var fieldFocused: Bool

    let isNew: Bool

    private let units = [
        "pcs", "m", "cm", "sheets", "rolls", "sets", "g", "ml"
    ]

    init(item: CraftItem, isNew: Bool) {
        _draft = State(initialValue: item)
        self.isNew = isNew
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && draft.quantity.isFinite
        && draft.quantity >= 0
        && !isLoadingPhoto
        && !requestingCamera
    }

    private var previewImage: UIImage? {
        if let photoData, let image = UIImage(data: photoData) {
            return image
        }
        if removePhoto { return nil }
        return PhotoStorage.image(filename: draft.photoFilename)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section("The Basics") {
                    TextField("Item name", text: $draft.name)
                        .focused($fieldFocused)
                    Picker("Category", selection: $draft.category) {
                        ForEach(CraftCategory.allCases) { category in
                            Text("\(category.emoji) \(category.title)")
                                .tag(category)
                        }
                    }
                }

                Section("How Much?") {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Quantity", value: $draft.quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .focused($fieldFocused)
                    }
                    Picker("Unit", selection: $draft.unit) {
                        ForEach(units, id: \.self) { unit in
                            Text(unit).tag(unit)
                        }
                    }
                }

                Section("Where Does It Live?") {
                    TextField("Location, e.g. Drawer A", text: $draft.location)
                        .focused($fieldFocused)
                }

                Section("Little Notes") {
                    TextField(
                        "Project ideas, colors, sizes...",
                        text: $draft.notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .focused($fieldFocused)
                }

                Section {
                    Text("Items and photos are saved on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(CabinetTheme.background)
            .navigationTitle(isNew ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveItem() }
                        .fontWeight(.bold)
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
            // 重新选择照片时，自动取消上一次尚未完成的加载。
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    acceptPhoto(image)
                }
                .ignoresSafeArea()
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(CabinetTheme.ink)
    }

    private var photoSection: some View {
        Section {
            VStack(spacing: 16) {
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .background(draft.category.color.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .accessibilityLabel("Item photo preview")
                } else {
                    VStack(spacing: 10) {
                        Text(draft.category.emoji)
                            .font(.system(size: 60))
                        Label("Add a little snapshot", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                        Text("Optional, but lovely to have.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(draft.category.color.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }

                if isLoadingPhoto {
                    ProgressView("Loading photo...")
                }

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingPhoto || requestingCamera)

                    Button {
                        openCamera()
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingPhoto || requestingCamera)
                }

                if previewImage != nil {
                    Button("Remove Photo", role: .destructive) {
                        selectedPhoto = nil
                        photoData = nil
                        removePhoto = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .disabled(isLoadingPhoto)
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.white.opacity(0.8))
        } header: {
            Text("A Picture of Your Treasure")
        }
    }

    @MainActor
    private func loadSelectedPhoto() async {
        guard let selection = selectedPhoto else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            guard let data = try await selection.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw PhotoError.invalidImage
            }
            try Task.checkCancellation()
            acceptPhoto(image)
        } catch is CancellationError {
            // 取消选择或离开表单，不显示错误。
        } catch {
            if !Task.isCancelled {
                errorMessage = "This photo couldn't be opened. Please try another image."
            }
        }
    }

    // 统一缩小并转换为 JPEG，减少存储空间和显示开销。
    private func acceptPhoto(_ image: UIImage) {
        do {
            photoData = try PhotoStorage.jpegData(from: image)
            removePhoto = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openCamera() {
        fieldFocused = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "No camera is available. Try this feature on your iPhone, or choose Library."
            return
        }
        // 避免项目尚未配置相机权限说明时直接崩溃。
        guard let description = Bundle.main.object(
            forInfoDictionaryKey: "NSCameraUsageDescription"
        ) as? String, !description.isEmpty else {
            errorMessage = "Add Privacy - Camera Usage Description in the Xcode target Info settings, then run the app again."
            return
        }

        requestingCamera = true
        Task { @MainActor in
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = await AVCaptureDevice.requestAccess(for: .video)
            default:
                granted = false
            }
            requestingCamera = false
            if granted {
                showingCamera = true
            } else {
                errorMessage = "Camera access is unavailable. You can allow it in Settings for CraftCabinet, or use Library instead."
            }
        }
    }

    private func saveItem() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid else { return }
        do {
            try store.save(draft, photoData: photoData, removePhoto: removePhoto)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 物品详情
struct ItemDetailView: View {
    @Environment(CabinetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingItem: CraftItem?
    @State private var showingFullPhoto = false
    @State private var showingDelete = false
    @State private var errorMessage: String?

    let itemID: UUID

    var body: some View {
        ScrollView {
            if let item = store.item(id: itemID) {
                VStack(spacing: 22) {
                    itemHeader(item)
                    informationCard(item)

                    Button {
                        editingItem = item
                    } label: {
                        Label("Edit Item", systemImage: "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(17)
                            .background(CabinetTheme.yellow)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 18)
                            )
                    }

                    if item.quantity > 0 {
                        Button {
                            markUsedUp(item)
                        } label: {
                            Label(
                                "Mark as Used Up",
                                systemImage: "checkmark.circle"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                    }

                    Button(role: .destructive) {
                        showingDelete = true
                    } label: {
                        Label("Delete Item", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 12)
                    }
                }
                .padding(22)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .background(CabinetTheme.background)
        .foregroundStyle(CabinetTheme.ink)
        .navigationTitle("Your Treasure")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editingItem) { item in
            ItemEditorView(item: item, isNew: false)
        }
        .alert("Delete this item?", isPresented: $showingDelete) {
            Button("Cancel", role: .cancel) { }

            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("This item will be removed from your cabinet.")
        }
        .alert(
            "Couldn't Update Item",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func itemHeader(_ item: CraftItem) -> some View {
        VStack(spacing: 16) {
            if let image = PhotoStorage.image(filename: item.photoFilename) {
                Button {
                    showingFullPhoto = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .background(item.category.color.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full photo")
                .sheet(isPresented: $showingFullPhoto) {
                    FullPhotoView(image: image)
                }
            } else {
                Text(item.category.emoji)
                    .font(.system(size: 76))
                    .frame(width: 160, height: 160)
                    .background(item.category.color)
                    .clipShape(RoundedRectangle(cornerRadius: 42))
                    .rotationEffect(.degrees(-5))
                    .accessibilityHidden(true)
            }

            Text(item.name)
                .font(.system(
                    size: 28,
                    weight: .bold,
                    design: .rounded
                ))
                .multilineTextAlignment(.center)

            Text(item.category.title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(item.category.color)
                .clipShape(Capsule())

            Text(item.quantityText)
                .font(.system(
                    size: 32,
                    weight: .heavy,
                    design: .rounded
                ))

            if item.quantity == 0 {
                Text("Used Up")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    private func informationCard(_ item: CraftItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Location", systemImage: "mappin.and.ellipse")
                .font(.headline)

            Text(
                item.location.isEmpty
                ? "No location added yet."
                : item.location
            )
            .foregroundStyle(.secondary)

            Divider()

            Label("Notes", systemImage: "note.text")
                .font(.headline)

            Text(
                item.notes.isEmpty
                ? "No little notes yet."
                : item.notes
            )
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func markUsedUp(_ item: CraftItem) {
        var updatedItem = item
        updatedItem.quantity = 0

        do {
            try store.save(updatedItem)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem() {
        do {
            try store.delete(id: itemID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 照片文件保存
// 图片保存成 JPEG 文件；JSON 只保存文件名。
enum PhotoError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "This image couldn't be processed. Please choose another photo."
    }
}

enum PhotoStorage {
    static func directory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = documents.appendingPathComponent("ItemPhotos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder
    }

    static func write(_ data: Data, filename: String) throws {
        let url = try directory().appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
    }

    static func image(filename: String?) -> UIImage? {
        guard let filename,
              let folder = try? directory() else { return nil }
        let url = folder.appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    // 清理失败不会撤销已经成功保存的物品记录。
    static func remove(filename: String?) {
        guard let filename,
              let folder = try? directory() else { return }
        let url = folder.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("Photo cleanup failed: \(error.localizedDescription)")
        }
    }

    // 限制最长边为 1600 像素，同时处理照片方向。
    static func jpegData(from image: UIImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw PhotoError.invalidImage
        }
        let ratio = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(
            width: max(1, (image.size.width * ratio).rounded()),
            height: max(1, (image.size.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.8) else {
            throw PhotoError.invalidImage
        }
        return data
    }
}

// MARK: - 列表照片缩略图
struct ItemPhotoView: View {
    let item: CraftItem

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                item.category.color
                if let image = PhotoStorage.image(filename: item.photoFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Text(item.category.emoji)
                        .font(.system(size: 30))
                }
            }
        }
    }
}

// MARK: - 完整照片预览
struct FullPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Full item photo")
            }
            .navigationTitle("Your Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.white)
                }
            }
        }
    }
}

// MARK: - 将系统相机接入 SwiftUI
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject,
        UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
