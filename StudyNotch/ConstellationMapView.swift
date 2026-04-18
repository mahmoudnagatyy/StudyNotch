import SwiftUI
import Observation

struct ConstellationMapView: View {
    var sessions = SessionStore.shared
    var subStore = SubjectStore.shared
    
    @State private var animateIn = false
    
    // Process sessions into relative star coordinates
    struct Star: Identifiable {
        let id: UUID
        let session: StudySession
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let color: Color
    }
    
    var stars: [Star] {
        let s = sessions.sessions.suffix(50) // Last 50 sessions
        guard !s.isEmpty else { return [] }
        
        let minTime = s.first!.startTime.timeIntervalSince1970
        let maxTime = s.last!.startTime.timeIntervalSince1970
        let timeRange = maxTime - minTime
        
        return s.map { session in
            let progress = timeRange > 0 ? (session.startTime.timeIntervalSince1970 - minTime) / timeRange : 0.5
            let x = 50 + CGFloat(progress) * 700 // Map time to X
            
            // Y is derived from subject hash to keep same subject stars on similar horizontal bands
            let hash = session.subject.hashValue
            let y = 100 + CGFloat(abs(hash) % 400)
            
            let size = 4 + CGFloat(min(session.duration / 1800.0, 8.0)) // Size by duration
            let color = subStore.color(for: session.subject)
            
            return Star(id: session.id, session: session, x: x, y: y, size: size, color: color)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Study Constellations").font(.system(size: 22, weight: .bold))
                    Text("Your sessions connected through time and subject.").font(.system(size: 13)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(24)
            
            // Galaxy Map
            ZStack {
                // Background stars (twinkle)
                ForEach(0..<100, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(Double.random(in: 0.1...0.3)))
                        .frame(width: 2, height: 2)
                        .position(x: CGFloat.random(in: 0...800), y: CGFloat.random(in: 0...600))
                }
                
                // Connections
                Canvas { context, size in
                    let starList = stars
                    for i in 0..<starList.count {
                        for j in i+1..<starList.count {
                            let s1 = starList[i]
                            let s2 = starList[j]
                            
                            // Only connect if same subject AND reasonably close in time
                            if s1.session.subject == s2.session.subject {
                                var path = Path()
                                path.move(to: CGPoint(x: s1.x, y: s1.y))
                                path.addLine(to: CGPoint(x: s2.x, y: s2.y))
                                
                                context.stroke(path, with: .color(s1.color.opacity(0.15)), lineWidth: 1)
                            }
                        }
                    }
                }
                .opacity(animateIn ? 1 : 0)
                
                // The Stars
                ForEach(stars) { star in
                    StarView(star: star, animate: animateIn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red:0.02, green:0.02, blue:0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                animateIn = true
            }
        }
    }
}

struct StarView: View {
    let star: ConstellationMapView.Star
    let animate: Bool
    
    @State private var pulsing = false
    
    var body: some View {
        ZStack {
            // Glow
            Circle()
                .fill(star.color.opacity(0.3))
                .frame(width: star.size * 3, height: star.size * 3)
                .blur(radius: 5)
                .scaleEffect(pulsing ? 1.2 : 0.8)
            
            // Core
            Circle()
                .fill(.white)
                .frame(width: star.size, height: star.size)
                .overlay(Circle().stroke(star.color, lineWidth: 1))
        }
        .position(x: star.x, y: star.y)
        .opacity(animate ? 1 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: Double.random(in: 1.5...3.0)).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
