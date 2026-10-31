//
//  MeetingSummary.swift
//  MeetingScribe
//
//  Khớp chuẩn xác 100% với JSON Schema trong PromptBuilder
//

import Foundation

public struct ContentItem: Codable, Identifiable, Equatable {
    public var id: String { "\(tieuDe)_\(noiDung.prefix(20))" }
    public let tieuDe: String
    public let noiDung: String

    enum CodingKeys: String, CodingKey {
        case tieuDe = "tieu_de"
        case noiDung = "noi_dung"
    }

    public init(tieuDe: String = "", noiDung: String = "") {
        self.tieuDe = tieuDe
        self.noiDung = noiDung
    }
}

public struct MeetingSummary: Codable, Equatable {
    public let tenCuocHop: String
    public let thoiGian: String
    public let diaDiem: String
    public let chuTri: String
    public let thuKy: String
    public let thanhPhan: [String]
    public let noiDungChinh: [ContentItem]
    public let ketLuan: [String]
    public let deXuat: [String]

    enum CodingKeys: String, CodingKey {
        case tenCuocHop = "ten_cuoc_hop"
        case thoiGian = "thoi_gian"
        case diaDiem = "dia_diem"
        case chuTri = "chu_tri"
        case thuKy = "thu_ky"
        case thanhPhan = "thanh_phan"
        case noiDungChinh = "noi_dung_chinh"
        case ketLuan = "ket_luan"
        case deXuat = "de_xuat"
    }

    public init(
        tenCuocHop: String = "",
        thoiGian: String = "",
        diaDiem: String = "",
        chuTri: String = "",
        thuKy: String = "",
        thanhPhan: [String] = [],
        noiDungChinh: [ContentItem] = [],
        ketLuan: [String] = [],
        deXuat: [String] = []
    ) {
        self.tenCuocHop = tenCuocHop
        self.thoiGian = thoiGian
        self.diaDiem = diaDiem
        self.chuTri = chuTri
        self.thuKy = thuKy
        self.thanhPhan = thanhPhan
        self.noiDungChinh = noiDungChinh
        self.ketLuan = ketLuan
        self.deXuat = deXuat
    }
}
