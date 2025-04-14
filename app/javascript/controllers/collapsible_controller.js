import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]
  
  toggle(event) {
    const targetId = event.currentTarget.dataset.id
    const targetElement = document.getElementById(targetId)
    
    if (targetElement) {
      targetElement.classList.toggle('hidden')
      
      // Toggle the arrow icon
      const iconElement = event.currentTarget.querySelector('svg')
      if (iconElement) {
        if (targetElement.classList.contains('hidden')) {
          iconElement.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />'
        } else {
          iconElement.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />'
        }
      }
    }
  }
}
