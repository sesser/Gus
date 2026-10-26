import GRDB

/// Catalog migrations. Each migration is append-only: never edit one that has
/// shipped, register a new one instead.
enum CatalogSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: createInitialSchema)
        migrator.registerMigration("v2", migrate: addImagePairs)
        migrator.registerMigration("v3", migrate: addKeywordSuggestions)
        migrator.registerMigration("v4", migrate: addMetadataAndAlbums)
        migrator.registerMigration("v5", migrate: addSidecarSync)
        migrator.registerMigration("v6", migrate: addImportPresets)
        migrator.registerMigration("v7", migrate: addVideos)
        migrator.registerMigration("v8", migrate: addAdjustmentPresets)
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

    /// On-device keyword suggestions. `analysisVersion` records which analysis
    /// looked at a master (NULL: not analyzed yet).
    private static func addKeywordSuggestions(_ db: Database) throws {
        try db.alter(table: "image") { t in
            t.add(column: "analysisVersion", .integer)
        }
        try db.create(table: "keywordSuggestion") { t in
            t.column("imageId", .integer).notNull()
                .references("image", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("confidence", .double).notNull()
            // 0 open, 1 accepted, 2 dismissed. Accepted and dismissed rows stay so
            // a later analysis does not offer the same keyword again.
            t.column("state", .integer).notNull().defaults(to: 0)
            t.primaryKey(["imageId", "name"])
        }
    }

    /// More metadata columns, import runs, local capture days, smart albums.
    /// Existing masters get one import run per project and their local day here;
    /// the new metadata columns fill in from a background re-read
    /// (`metadataRevision` 1 means not read yet).
    private static func addMetadataAndAlbums(_ db: Database) throws {
        try db.create(table: "importRun") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("startedAt", .datetime).notNull()
            t.column("sourcePath", .text)
            t.column("projectId", .integer).indexed()
                .references("project", onDelete: .setNull)
        }
        try db.alter(table: "image") { t in
            t.add(column: "importRunId", .integer).references("importRun", onDelete: .setNull)
            t.add(column: "localDate", .text)
            t.add(column: "artist", .text)
            t.add(column: "copyright", .text)
            t.add(column: "caption", .text)
            t.add(column: "cameraSerial", .text)
            t.add(column: "latitude", .double)
            t.add(column: "longitude", .double)
            t.add(column: "flashFired", .boolean)
            t.add(column: "exposureCompensation", .double)
            t.add(column: "whiteBalance", .integer)
            t.add(column: "exposureProgram", .integer)
            t.add(column: "meteringMode", .integer)
            t.add(column: "focalLength35mm", .double)
            t.add(column: "metadataRevision", .integer).notNull().defaults(to: 1)
        }
        try db.create(index: "image_on_localDate", on: "image", columns: ["localDate"])
        try db.create(index: "image_on_importRunId", on: "image", columns: ["importRunId"])
        try db.create(table: "smartAlbum") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("projectId", .integer).indexed()
                .references("project", onDelete: .cascade)
            t.column("rules", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }

        try db.execute(sql: """
            INSERT INTO importRun (startedAt, sourcePath, projectId)
            SELECT createdAt, sourcePath, id FROM project ORDER BY createdAt, id
            """)
        try db.execute(sql: """
            UPDATE image SET importRunId = (SELECT id FROM importRun WHERE importRun.projectId = image.projectId)
            """)
        let update = try db.makeStatement(sql: "UPDATE image SET localDate = ? WHERE id = ?")
        let rows = try Row.fetchCursor(db, sql: "SELECT id, captureDate, captureOffsetSeconds, modifiedAt FROM image")
        while let row = try rows.next() {
            let day = LocalDate.string(captureDate: row["captureDate"], offset: row["captureOffsetSeconds"],
                                       fallback: row["modifiedAt"])
            try update.execute(arguments: [day, row["id"] as Int64])
        }
    }

    /// Saved adjustments; `settings` is edit stack JSON.
    private static func addAdjustmentPresets(_ db: Database) throws {
        try db.create(table: "adjustmentPreset") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("settings", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
    }

    /// Videos: their length. Their kind follows from `format`.
    private static func addVideos(_ db: Database) throws {
        try db.alter(table: "image") { t in
            t.add(column: "duration", .double)
        }
    }

    /// Saved metadata presets for imports (creator, copyright, contact…).
    private static func addImportPresets(_ db: Database) throws {
        try db.create(table: "importPreset") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("uuid", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("settings", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
    }

    /// XMP sidecar bookkeeping.
    ///
    /// `metadataSync` holds, per master that owns a sidecar (a pair's RAW, or a
    /// single master), what the file looked like when the app last read or
    /// wrote it, the values at that moment (the baseline), and a status.
    /// `sidecarQueue` lists masters whose values changed since; triggers fill
    /// it, so every path that changes culling, keywords or descriptive fields
    /// (including undo) is covered.
    private static func addSidecarSync(_ db: Database) throws {
        try db.alter(table: "image") { t in
            t.add(column: "creatorContact", .text)
            t.add(column: "usageTerms", .text)
        }
        try db.create(table: "metadataSync") { t in
            t.primaryKey("imageId", .integer)
                .references("image", onDelete: .cascade)
            t.column("sidecarName", .text)
            t.column("sidecarSize", .integer)
            t.column("sidecarModifiedAt", .datetime)
            t.column("sidecarDigest", .text)
            t.column("baseline", .text).notNull()
            // 0 in step, 1 changed outside the app (waiting for review), 2 write failed.
            t.column("status", .integer).notNull().defaults(to: 0)
            t.column("diskValues", .text)
            // 0 the sidecar, 1 metadata embedded in the master.
            t.column("diskSource", .integer).notNull().defaults(to: 0)
            t.column("checkedAt", .datetime)
            t.column("error", .text)
        }
        try db.create(index: "metadataSync_on_status", on: "metadataSync", columns: ["status"])
        try db.create(table: "sidecarQueue") { t in
            t.primaryKey("imageId", .integer)
        }
        try db.execute(sql: """
            CREATE TRIGGER sidecar_culling AFTER UPDATE OF rating, flag, colorLabel ON version
            WHEN NEW.isDefault AND (OLD.rating IS NOT NEW.rating OR OLD.flag IS NOT NEW.flag
                                    OR OLD.colorLabel IS NOT NEW.colorLabel)
            BEGIN INSERT OR IGNORE INTO sidecarQueue (imageId) VALUES (NEW.imageId); END;

            CREATE TRIGGER sidecar_keyword_added AFTER INSERT ON versionKeyword
            BEGIN
                INSERT OR IGNORE INTO sidecarQueue (imageId)
                SELECT imageId FROM version WHERE id = NEW.versionId AND isDefault;
            END;

            CREATE TRIGGER sidecar_keyword_removed AFTER DELETE ON versionKeyword
            BEGIN
                INSERT OR IGNORE INTO sidecarQueue (imageId)
                SELECT imageId FROM version WHERE id = OLD.versionId AND isDefault;
            END;

            CREATE TRIGGER sidecar_keyword_renamed AFTER UPDATE OF name ON keyword
            WHEN OLD.name IS NOT NEW.name
            BEGIN
                INSERT OR IGNORE INTO sidecarQueue (imageId)
                SELECT version.imageId FROM versionKeyword JOIN version ON version.id = versionKeyword.versionId
                WHERE versionKeyword.keywordId = NEW.id AND version.isDefault;
            END;

            CREATE TRIGGER sidecar_description AFTER UPDATE OF artist, copyright, caption, usageTerms, creatorContact ON image
            WHEN OLD.artist IS NOT NEW.artist OR OLD.copyright IS NOT NEW.copyright OR OLD.caption IS NOT NEW.caption
                 OR OLD.usageTerms IS NOT NEW.usageTerms OR OLD.creatorContact IS NOT NEW.creatorContact
            BEGIN INSERT OR IGNORE INTO sidecarQueue (imageId) VALUES (NEW.id); END;
            """)
    }
}
