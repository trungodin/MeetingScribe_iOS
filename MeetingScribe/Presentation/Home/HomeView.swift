//
//  HomeView.swift
//  MeetingScribe
//
//  Màn hình chính danh sách cuộc họp
//

import SwiftUI

public struct HomeView: View {
    @StateObject private var store = MeetingStore.shared
    @State private var showingRecord = false
    @State private var showingSettings = false
    @State private var selectedMeeting: Meeting?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if store.meetings.isEmpty {
                    emptyStateView
                } else {
                    meetingListView
                }
            }
            .navigationTitle("MeetingScribe VN")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                recordFloatingButton
            }
            .sheet(isPresented: $showingRecord) {
                RecordView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(item: $selectedMeeting) { meeting in
                DetailView(meetingId: meeting.id)
            }
            .onAppear {
                store.loadMeetings()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Chưa có cuộc họp nào")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Nhấn nút tròn đỏ bên dưới để bắt đầu ghi âm cuộc họp mới")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var meetingListView: some View {
        List {
            ForEach(store.meetings) { meeting in
                MeetingRowView(meeting: meeting)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMeeting = meeting
                    }
            }
            .onDelete(perform: deleteMeetings)
        }
        .listStyle(.insetGrouped)
    }

    private var recordFloatingButton: some View {
        Button(action: { showingRecord = true }) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                Text("Ghi âm mới")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(30)
            .shadow(color: Color.red.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .padding(24)
    }

    private func deleteMeetings(offsets: IndexSet) {
        for index in offsets {
            let id = store.meetings[index].id
            store.delete(id: id)
        }
    }
}

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .foregroundColor(.primary)

            HStack {
                Label(meeting.formattedCreatedAt, systemImage: "calendar")
                Spacer()
                Label(meeting.formattedDuration, systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text(meeting.status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15))
                .foregroundColor(statusColor)
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch meeting.status {
        case .recorded: return .gray
        case .transcribing, .summarizing: return .orange
        case .transcribed: return .blue
        case .summarized: return .purple
        case .exported: return .green
        }
    }
}
