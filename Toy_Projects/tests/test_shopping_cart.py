from Toy_Projects.shopping_cart import ShoppingCart
import pytest


class TestShoppingCart:
    @pytest.fixture
    def setup_cart(self):
        return ShoppingCart()

    def test_add_item(self, setup_cart):
        setup_cart.add_item("Apple", 1.5)
        assert setup_cart.get_total_count() == 1
        assert setup_cart.get_total_price() == 1.5

    def test_add_multiple_items(self, setup_cart):
        setup_cart.add_item("Apple", 1.5)
        setup_cart.add_item("Banana", 2.0)
        assert setup_cart.get_total_count() == 2
        assert setup_cart.get_total_price() == 3.5

    def test_remove_item(self, setup_cart):
        setup_cart.add_item("Apple", 1.5)
        setup_cart.add_item("Banana", 2.0)
        removed_value = setup_cart.remove_item("Apple")
        assert removed_value == 1.5
        assert setup_cart.get_total_count() == 1
        assert setup_cart.get_total_price() == 2.0
        assert "Apple" not in setup_cart.get_items()

    def test_add_item_with_invalid_price(self, setup_cart):
        with pytest.raises(ValueError):
            setup_cart.add_item("Invalid Item", -1.5)
