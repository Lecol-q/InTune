//
//  MusicCardView.swift
//  InTune
//
//  Created by Collin Le on 9/30/26.
//

import SwiftUI
import UIKit

struct MusicCardView: View {
    var body: some View {
        CardView()
    }
}

struct CardView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController {
        ViewController()
    }
    
    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        
    }
}


class ViewController: UIViewController, SwipeCardStackDataSource {
  let cardStack = SwipeCardStack()
  
  let cardImages = [
      UIImage(named: "cardImage1"),
      UIImage(named: "cardImage2"),
      UIImage(named: "cardImage3")
  ]
  
  override func viewDidLoad() {
    super.viewDidLoad()
    view.addSubview(cardStack)
    cardStack.frame = CGRect(
        x: 20,
        y: 100,
        width: view.bounds.width - 40,
        height: view.bounds.height - 200)
      cardStack.dataSource = self
  }
    
    func numberOfCards(in cardStack: SwipeCardStack) -> Int {
        return 1
    }

    func cardStack(_ cardStack: SwipeCardStack, cardForIndexAt index: Int) -> SwipeCard {
        let card = SwipeCard()
        
        let content = UIView()
        content.backgroundColor = .blue
        content.layer.cornerRadius = 30
        card.content = content
        let button = UIButton(type: .system)
        button.setTitle("", for: .normal)
        content.addSubview(button)
        
        
        button.frame = CGRect(x: 20, y: 20, width: 100, height: 50)
        
        return card
    }
    
    func play(){
        
    }
}

#Preview {
    MusicCardView()
}
