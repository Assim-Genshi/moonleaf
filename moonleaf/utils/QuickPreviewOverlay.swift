//
//  QuickPreviewOverlay.swift
//  moonleaf
//
//  Copyright © 2026 naomisphere. All rights reserved.
//

import SwiftUI
import AVKit

struct QuickPreviewOverlay: View {
    let wallpaper: endup_wp
    let onClose: () -> Void
    
    @State private var isHovered = false
    @State private var currentTime = Date()
    @State private var isVisible = false
    @State private var player: AVPlayer?
    @State private var isVideoPlaying = true
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var fileExtension: String {
        (wallpaper.path as NSString).pathExtension.lowercased()
    }
    
    var body: some View {
        ZStack {
            
            Color.black
                .ignoresSafeArea()
            
            
            Group {
                let ext = fileExtension
                
                if ["mp4", "mov"].contains(ext) {
                    
                    if let player = player {
                        VideoPlayer(player: player)
                            .onAppear {
                                if isVideoPlaying {
                                    player.play()
                                }
                            }
                            .onDisappear {
                                player.pause()
                            }
                            .onTapGesture {
                                if isVideoPlaying {
                                    player.pause()
                                } else {
                                    player.play()
                                }
                                isVideoPlaying.toggle()
                            }
                            .overlay(
                                Group {
                                    if !isVideoPlaying {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.white.opacity(0.6))
                                            .shadow(color: .black.opacity(0.5), radius: 10)
                                    }
                                }
                            )
                    } else {
                        Color.gray.opacity(0.3)
                            .overlay {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }
                    }
                } else if ext == "gif" {
                    
                    GIFAnimatingView(path: wallpaper.path)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if ["jpg", "jpeg", "png"].contains(ext) {
                    
                    if let image = NSImage(contentsOfFile: wallpaper.path) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Color.gray.opacity(0.3)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                    }
                } else {
                    Color.gray.opacity(0.3)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.5))
                        }
                }
            }
            .ignoresSafeArea()
            
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        
                        Text(formatDate(currentTime))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.bottom, -3)
                        
                        
                        Text(formatTime(currentTime))
                            .font(.system(size: 96, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                    }
                    .padding(.top, 60)
                    Spacer()
                }
                Spacer()
            }
            .ignoresSafeArea()
            
            
            VStack {
                Spacer()
                
                HStack(spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wallpaper.name)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                        
                        let ext = fileExtension
                        let fileType = ["mp4", "mov"].contains(ext) ? "Video" :
                                      ext == "gif" ? "GIF" :
                                      ["jpg", "jpeg", "png"].contains(ext) ? "Image" : "File"
                        Text("\(fileType) • \(ByteCountFormatter.string(fromByteCount: wallpaper.fileSize, countStyle: .file))")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    
                    if ["mp4", "mov"].contains(fileExtension) {
                        Button(action: {
                            if isVideoPlaying {
                                player?.pause()
                            } else {
                                player?.play()
                            }
                            isVideoPlaying.toggle()
                        }) {
                            Image(systemName: isVideoPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 5)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    
                    
                    Button(action: onClose) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Close Preview")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(.regularMaterial.opacity(0.8))
                                .overlay {
                                    Capsule()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHovered = hovering
                        }
                    }
                    // .scaleEffect(isHovered ? 1.05 : 1.0)
                    
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.2), value: isVisible)
        }
        .onAppear {
            
            let ext = fileExtension
            if ["mp4", "mov"].contains(ext) {
                let url = URL(fileURLWithPath: wallpaper.path)
                player = AVPlayer(url: url)
                player?.volume = 0 
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    player?.play()
                }
            }
            
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

struct GIFAnimatingView: NSViewRepresentable {
    let path: String
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let image = NSImage(contentsOfFile: path) {
            nsView.image = image
        }
    }
}