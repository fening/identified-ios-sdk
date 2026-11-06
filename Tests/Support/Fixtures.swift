import Foundation
import IdentifiedCore

/// JSON shaped exactly like the backend's responses
/// (`cmd/session-service/main.go` hostedSessionView, `internal/model/models.go`).
/// Tests start from a base object and override fields, so each test states only
/// what it cares about.
package enum Fixtures {
    package static func sessionJSON(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "id": "sess-1",
            "subject_ref": "driver-42",
            "profile_key": "standard_identity",
            "tenant_id": "tenant-1",
            "environment": "test",
            "status": "active",
            "expires_at": "2026-11-02T12:30:00Z",
            "required_documents": ["license_front", "license_back", "selfie"],
            "required_checks": ["id_document", "biometric_liveness", "biometric_face_match"],
            "collect_name": true,
            "allowed_id_types": NSNull(),
            "branding": ["display_name": "Acme"],
            "correction_applied": false,
            "consent_recorded": false,
            "identity_name_complete": false,
            "identity_details_complete": false,
            "id_details": [String: Any](),
        ]
        for (key, value) in overrides { base[key] = value }
        return base
    }

    package static func caseJSON(status: String = "draft", documents: [[String: Any]] = [], overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "id": "case-1",
            "user_id": "sess-1",
            "environment": "test",
            "subject_id": "driver-42",
            "status": status,
            "required_documents": ["license_front", "license_back", "selfie"],
            "required_checks": ["id_document", "biometric_liveness", "biometric_face_match"],
            "created_at": "2026-11-02T12:00:00Z",
            "updated_at": "2026-11-02T12:00:00Z",
            "documents": documents,
        ]
        for (key, value) in overrides { base[key] = value }
        return base
    }

    package static func document(_ docType: String, role: String? = nil, status: String = "pending", superseded: Bool = false) -> [String: Any] {
        var doc: [String: Any] = [
            "id": UUID().uuidString,
            "case_id": "case-1",
            "doc_type": docType,
            "file_url": "https://files.example/\(docType)",
            "superseded": superseded,
            "status": status,
            "uploaded_at": "2026-11-02T12:01:00Z",
        ]
        if let role { doc["capture_role"] = role }
        return doc
    }

    package static func data(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    package static func enveloped(_ object: Any) -> Data {
        data(["data": object])
    }

    package static func session(_ overrides: [String: Any] = [:]) -> HostedSession {
        try! JSONDecoder.identified.decode(HostedSession.self, from: data(sessionJSON(overrides)))
    }

    package static func verificationCase(status: String = "draft", documents: [[String: Any]] = [], overrides: [String: Any] = [:]) -> VerificationCase {
        try! JSONDecoder.identified.decode(VerificationCase.self, from: data(caseJSON(status: status, documents: documents, overrides: overrides)))
    }
}
