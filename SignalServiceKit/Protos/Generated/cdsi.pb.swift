//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: cdsi.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct CDSI_ClientRequest: @unchecked Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Each ACI/UAK pair is a 32-byte buffer, containing the 16-byte ACI followed
  /// by its 16-byte UAK.
  var aciUakPairs: Data = Data()

  /// Each E164 is an 8-byte big-endian number, as 8 bytes.
  var prevE164S: Data = Data()

  var newE164S: Data = Data()

  var discardE164S: Data = Data()

  /// If set, a token which allows rate limiting to discount the e164s in
  /// the request's prev_e164s, only counting new_e164s.  If not set, then
  /// rate limiting considers both prev_e164s' and new_e164s' size.
  var token: Data = Data()

  /// After receiving a new token from the server, send back a message just
  /// containing a token_ack.
  var tokenAck: Bool = false

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

struct CDSI_ClientResponse: @unchecked Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Each triple is an 8-byte e164, a 16-byte PNI, and a 16-byte ACI.
  /// If the e164 was not found, PNI and ACI are all zeros.  If the PNI
  /// was found but the ACI was not, the PNI will be non-zero and the ACI
  /// will be all zeros.  ACI will be returned if one of the returned
  /// PNIs has an ACI/UAK pair that matches.
  ///
  /// Should the request be successful (IE: a successful status returned),
  /// |e164_pni_aci_triple| will always equal |e164| of the request,
  /// so the entire marshalled size of the response will be (2+32)*|e164|,
  /// where the additional 2 bytes are the id/type/length additions of the
  /// protobuf marshaling added to each byte array.  This avoids any data
  /// leakage based on the size of the encrypted output.
  var e164PniAciTriples: Data = Data()

  /// A token which allows subsequent calls' rate limiting to discount the
  /// e164s sent up in this request, only counting those in the next
  /// request's new_e164s.
  var token: Data = Data()

  /// On a successful response to a token_ack request, the number of permits
  /// that were deducted from the user's rate-limit in order to process the
  /// request
  var debugPermitsUsed: Int32 = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "CDSI"

extension CDSI_ClientRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ClientRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "aci_uak_pairs"),
    2: .standard(proto: "prev_e164s"),
    3: .standard(proto: "new_e164s"),
    4: .standard(proto: "discard_e164s"),
    6: .same(proto: "token"),
    7: .standard(proto: "token_ack"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.aciUakPairs) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.prevE164S) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self.newE164S) }()
      case 4: try { try decoder.decodeSingularBytesField(value: &self.discardE164S) }()
      case 6: try { try decoder.decodeSingularBytesField(value: &self.token) }()
      case 7: try { try decoder.decodeSingularBoolField(value: &self.tokenAck) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.aciUakPairs.isEmpty {
      try visitor.visitSingularBytesField(value: self.aciUakPairs, fieldNumber: 1)
    }
    if !self.prevE164S.isEmpty {
      try visitor.visitSingularBytesField(value: self.prevE164S, fieldNumber: 2)
    }
    if !self.newE164S.isEmpty {
      try visitor.visitSingularBytesField(value: self.newE164S, fieldNumber: 3)
    }
    if !self.discardE164S.isEmpty {
      try visitor.visitSingularBytesField(value: self.discardE164S, fieldNumber: 4)
    }
    if !self.token.isEmpty {
      try visitor.visitSingularBytesField(value: self.token, fieldNumber: 6)
    }
    if self.tokenAck != false {
      try visitor.visitSingularBoolField(value: self.tokenAck, fieldNumber: 7)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CDSI_ClientRequest, rhs: CDSI_ClientRequest) -> Bool {
    if lhs.aciUakPairs != rhs.aciUakPairs {return false}
    if lhs.prevE164S != rhs.prevE164S {return false}
    if lhs.newE164S != rhs.newE164S {return false}
    if lhs.discardE164S != rhs.discardE164S {return false}
    if lhs.token != rhs.token {return false}
    if lhs.tokenAck != rhs.tokenAck {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension CDSI_ClientResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ClientResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "e164_pni_aci_triples"),
    3: .same(proto: "token"),
    4: .standard(proto: "debug_permits_used"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.e164PniAciTriples) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self.token) }()
      case 4: try { try decoder.decodeSingularInt32Field(value: &self.debugPermitsUsed) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.e164PniAciTriples.isEmpty {
      try visitor.visitSingularBytesField(value: self.e164PniAciTriples, fieldNumber: 1)
    }
    if !self.token.isEmpty {
      try visitor.visitSingularBytesField(value: self.token, fieldNumber: 3)
    }
    if self.debugPermitsUsed != 0 {
      try visitor.visitSingularInt32Field(value: self.debugPermitsUsed, fieldNumber: 4)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CDSI_ClientResponse, rhs: CDSI_ClientResponse) -> Bool {
    if lhs.e164PniAciTriples != rhs.e164PniAciTriples {return false}
    if lhs.token != rhs.token {return false}
    if lhs.debugPermitsUsed != rhs.debugPermitsUsed {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
