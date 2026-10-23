import GRDB

/// Catalog migrations. Each migration is append-only: never edit one that has
/// shipped, register a new one instead.
enum CatalogSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: createInitialSchema)
        migrator.registerMigration("v2", migrate: addImagePairs)
        return migrator
    }

    private static func createInitialSchema(_ db: Database) throws {
        try db.create(table: "volume") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("identity", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("mountPath", .text).notNull()
            t.column("isRemovable", .boolean).notNull().defaults(to: false)
            t.column("isNetwork", .boolean).notNull().defaults(to: false)
            t.column("lastSeenAt", .datetime)
        }

        try db.create(table: "project") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("sourcePath", .text)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "image") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("volumeId", .integer).notNull().indexed()
                .references("volume", onDelete: .restrict)
            t.column("projectId", .integer).notNull().indexed()
                .references("project", onDelete: .cascade)
            t.column("relativePath", .text).notNull()
            t.column("fileName", .text).notNull()
            t.column("fileSize", .integer).notNull()
            t.column("modifiedAt", .datetime).notNull()
            t.column("contentHash", .text).notNull().unique()
            t.column("format", .text).notNull()
            t.column("captureDate", .datetime)
            t.column("captureOffsetSeconds", .integer)
            t.column("sortDate", .datetime).notNull().indexed()
            t.column("pixelWidth", .integer)
            t.column("pixelHeight", .integer)
            t.column("orientation", .integer).notNull().defaults(to: 1)
                .check(sql: "orientation BETWEEN 1 AND 8")
            t.column("cameraMake", .text)
            t.column("cameraModel", .text)
            t.column("lensModel", .text)
            t.column("iso", .integer)
            t.column("exposureTime", .double)
            t.column("fNumber", .double)
            t.column("focalLength", .double)
            t.column("importedAt", .datetime).notNull()
            t.uniqueKey(["volumeId", "relativePath"])
        }

        try db.create(table: "version") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("imageId", .integer).notNull()
                .references("image", onDelete: .cascade)
            t.column("versionNumber", .integer).notNull()
            t.column("name", .text)
            t.column("isDefault", .boolean).notNull().defaults(to: false)
            t.column("rating", .integer).notNull().defaults(to: 0)
                .check(sql: "rating BETWEEN 0 AND 5")
            t.column("flag", .integer).notNull().defaults(to: 0)
                .check(sql: "flag IN (-1, 0, 1)")
            t.column("colorLabel", .integer).notNull().defaults(to: 0)
                .check(sql: "colorLabel BETWEEN 0 AND 7")
            t.column("editStack", .text).notNull()
            t.column("editStackHash", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("modifiedAt", .datetime).notNull()
            t.uniqueKey(["imageId", "versionNumber"])
        }
        try db.execute(sql: "CREATE UNIQUE INDEX version_one_default_per_image ON version(imageId) WHERE isDefault")
        try db.create(index: "version_on_rating", on: "version", columns: ["rating"])
        try db.create(index: "version_on_flag", on: "version", columns: ["flag"])

        try db.create(table: "album") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("projectId", .integer).indexed()
                .references("project", onDelete: .cascade)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "albumMember") { t in
            t.column("albumId", .integer).notNull()
                .references("album", onDelete: .cascade)
            t.column("versionId", .integer).notNull().indexed()
                .references("version", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["albumId", "versionId"])
        }

        try db.create(table: "stack") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("pickVersionId", .integer)
                .references("version", onDelete: .setNull)
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "stackMember") { t in
            t.column("stackId", .integer).notNull().indexed()
                .references("stack", onDelete: .cascade)
            // A version is in at most one stack.
            t.column("versionId", .integer).notNull().unique()
                .references("version", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.primaryKey(["stackId", "versionId"])
        }

        try db.create(table: "keyword") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("parentId", .integer).indexed()
                .references("keyword", onDelete: .cascade)
        }
        // NULL parents compare as distinct in plain UNIQUE constraints, so root-level
        // uniqueness needs an expression index.
        try db.execute(sql: "CREATE UNIQUE INDEX keyword_unique_name ON keyword(ifnull(parentId, 0), name COLLATE NOCASE)")

        try db.create(table: "versionKeyword") { t in
            t.column("versionId", .integer).notNull()
                .references("version", onDelete: .cascade)
            t.column("keywordId", .integer).notNull().indexed()
                .references("keyword", onDelete: .cascade)
            t.primaryKey(["versionId", "keywordId"])
        }
    }

    /// RAW+JPEG pairs. Existing masters get their pairing keys and are paired here;
    /// culling values, keywords and albums of the two halves are merged.
    private static func addImagePairs(_ db: Database) throws {
        try db.alter(table: "image") { t in
            t.add(column: "pairingKey", .text)
        }
        try db.create(index: "image_on_pairingKey", on: "image", columns: ["volumeId", "pairingKey"])
        try db.create(table: "imagePair") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("rawImageId", .integer).notNull().unique()
                .references("image", onDelete: .cascade)
            t.column("companionImageId", .integer).notNull().unique()
                .references("image", onDelete: .cascade)
            t.column("showsCompanion", .boolean).notNull().defaults(to: false)
        }

        let update = try db.makeStatement(sql: "UPDATE image SET pairingKey = ? WHERE id = ?")
        let rows = try Row.fetchCursor(db, sql: "SELECT id, relativePath FROM image")
        while let row = try rows.next() {
            let path: String = row["relativePath"]
            try update.execute(arguments: [ImagePairing.key(forRelativePath: path), row["id"] as Int64])
        }
        try ImagePairing.pairAll(db)
    }
}
