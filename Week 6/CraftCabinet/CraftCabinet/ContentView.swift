import SwiftUI
import Observation

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

    // 相同 ID 表示编辑，否则表示新增。
    func save(_ item: CraftItem) throws {
        var updatedItems = items

        if let index = updatedItems.firstIndex(
            where: { $0.id == item.id }
        ) {
            updatedItems[index] = item
        } else {
            updatedItems.insert(item, at: 0)
        }

        try commit(updatedItems)
    }

    func delete(id: UUID) throws {
        try commit(items.filter { $0.id != id })
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
            Text(item.category.emoji)
                .font(.system(size: 30))
                .frame(width: 62, height: 66)
                .background(item.category.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: 18)
                )
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

    let isNew: Bool

    private let units = [
        "pcs", "m", "cm", "sheets",
        "rolls", "sets", "g", "ml"
    ]

    init(item: CraftItem, isNew: Bool) {
        _draft = State(initialValue: item)
        self.isNew = isNew
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        && draft.quantity.isFinite
        && draft.quantity >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()

                        Text(draft.category.emoji)
                            .font(.system(size: 64))
                            .padding(20)
                            .background(draft.category.color)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 28)
                            )
                            .accessibilityHidden(true)

                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("The Basics") {
                    TextField("Item name", text: $draft.name)

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

                        TextField(
                            "Quantity",
                            value: $draft.quantity,
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                    }

                    Picker("Unit", selection: $draft.unit) {
                        ForEach(units, id: \.self) { unit in
                            Text(unit).tag(unit)
                        }
                    }
                }

                Section("Where Does It Live?") {
                    TextField(
                        "Location, e.g. Drawer A",
                        text: $draft.location
                    )
                }

                Section("Little Notes") {
                    TextField(
                        "Project ideas, colors, sizes...",
                        text: $draft.notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section {
                    Text("Your items are saved on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CabinetTheme.background)
            .navigationTitle(isNew ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveItem()
                    }
                    .fontWeight(.bold)
                    .disabled(!isValid)
                }
            }
            .alert(
                "Couldn't Save",
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
        .tint(CabinetTheme.ink)
    }

    private func saveItem() {
        draft.name = draft.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        draft.location = draft.location.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard isValid else { return }

        do {
            try store.save(draft)
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
            Text(item.category.emoji)
                .font(.system(size: 76))
                .frame(width: 160, height: 160)
                .background(item.category.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: 42)
                )
                .rotationEffect(.degrees(-5))
                .accessibilityHidden(true)

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
