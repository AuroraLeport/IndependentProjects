class ShoppingCart:
    def __init__(self):
        self._items = {}
        
    def add_item(self, item_name, price):
        if price <=0:
            raise ValueError("Price must be positive")
        self._items[item_name] = price
        
    def get_total_price(self):
        return sum(self._items.values())
    
    def get_total_count(self):
        return len(self._items)
    
    def remove_item(self, item_name):
        if item_name not in self._items:
            raise KeyError(f"Item '{item_name}' not in cart")
        return self._items.pop(item_name, None)
    
    def get_items(self):
        return self._items
                