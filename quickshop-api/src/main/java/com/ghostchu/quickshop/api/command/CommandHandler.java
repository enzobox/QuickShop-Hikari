package com.ghostchu.quickshop.api.command;

import com.ghostchu.quickshop.api.QuickShopAPI;
import com.ghostchu.quickshop.api.shop.Shop;
import org.bukkit.block.Block;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.util.BlockIterator;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

/**
 * The command handler that processing sub commands under QS main command
 *
 * @param <T> The required sender class you want, must is the subtype of {@link CommandSender}
 */
public interface CommandHandler<T extends CommandSender> {



  default Shop findShop(final T sender, final CommandParser parser, final int idIndex) {

    final Shop shop = getLookingShop(sender);
    if(parser.getArgs().size() >= (idIndex + 1)) {

      try {

        final long shopID = Long.parseLong(parser.getArgs().get(idIndex));
        return QuickShopAPI.getInstance().getShopManager().getShop(shopID);
      } catch(final Exception ignore) { }
    }

    return shop;
  }

  /**
   * Getting the player now looking shop
   *
   * @return The shop that player looking or null if not found
   *
   * @throws IllegalStateException if sender is not player
   */
  @Nullable
  default Shop getLookingShop(final T sender) throws IllegalStateException {

    if(sender instanceof final Player player) {
      final BlockIterator bIt = new BlockIterator(player, 10);
      while(bIt.hasNext()) {
        final Block b = bIt.next();
        final Shop shop = QuickShopAPI.getInstance().getShopManager().getShop(b.getLocation());
        if(shop == null) {
          continue;
        }
        return shop;
      }
      // boxmc (BUG-0655): the ray above starts at the SERVER-side eye. A Bedrock player whose
      // minecraft:scale attribute is not 1 (EssencePowers axolotl 0.5, frog 0.7, dragon/giraffe 1.2)
      // has a server eye far from where his client camera actually is (Geyser keeps the camera at
      // normal height), so he aims at the shop sign while the server ray passes under/over the shop.
      // Only when the normal ray found nothing, retry once from the unscaled eye height.
      return boxmcLookingShopFromUnscaledEye(player);
    }
    throw new IllegalStateException("Sender is not player");
  }

  /**
   * boxmc (BUG-0655) fallback for {@link #getLookingShop(CommandSender)}: when the player's current eye height differs
   * from the vanilla unscaled eye height (1.62 standing, 1.27 sneaking) by more than 0.05 blocks, cast one more ray from
   * the same feet location at the unscaled eye height, along the same look direction, max 10 blocks, with the same exact
   * block shop lookup. Returns null when the eye height is (near) vanilla, so unscaled players see no behaviour change.
   * No Floodgate dependency: a scaled Java player only ever reaches this when his own correct ray found nothing.
   */
  @Nullable
  private static Shop boxmcLookingShopFromUnscaledEye(@NotNull final Player player) {

    final double unscaledEye = player.isSneaking()? 1.27D : 1.62D;
    if(Math.abs(player.getEyeHeight() - unscaledEye) <= 0.05D) {
      return null;
    }
    // getLocation() carries the same yaw/pitch as the eye location; the yOffset lifts the start to the unscaled eye.
    final BlockIterator bIt = new BlockIterator(player.getLocation(), unscaledEye, 10);
    while(bIt.hasNext()) {
      final Block b = bIt.next();
      final Shop shop = QuickShopAPI.getInstance().getShopManager().getShop(b.getLocation());
      if(shop != null) {
        return shop;
      }
    }
    return null;
  }

  default @NotNull CompletableFuture<@NotNull List<Shop>> getTaggedShops(final T sender, @NotNull final String tag) {

    if(sender instanceof final Player player) {
      final UUID tagger = player.getUniqueId();
      return QuickShopAPI.getInstance().getShopManager().queryTaggedShops(tagger, tag);
    }
    throw new IllegalStateException("Sender is not player");
  }

  /**
   * Getting the shops by ids
   *
   * @param ids The shop ids
   *
   * @return The shops
   */
  @Nullable
  default Map<Long, Shop> getShopsByIds(@NotNull final List<Long> ids) {

    final Map<Long, Shop> shops = new HashMap<>();
    for(final Long id : ids) {
      shops.put(id, QuickShopAPI.getInstance().getShopManager().getShop(id));
    }
    return shops;
  }

  default void onCommand_Internal(final T sender, @NotNull final String commandLabel, @NotNull final String[] cmdArg) {

    final StringJoiner joiner = new StringJoiner(" ");
    for(final String s : cmdArg) {
      joiner.add(s);
    }

    final CommandParser parser = new CommandParser(joiner.toString(), true);
    try {
      onCommand(sender, commandLabel, parser);
    } catch(final UnsupportedOperationException ignore) {
      try {
        onCommand(sender, commandLabel, parser.getArgs().toArray(new String[0]));
      } catch(final UnsupportedOperationException ignored) {

      }
    }
  }

  /**
   * Calling while command executed by specified sender
   *
   * @param sender       The command sender but will automatically convert to specified instance
   * @param commandLabel The command prefix (/quickshop = qs, /shop = shop)
   * @param parser       The command parser which include arguments and colon arguments
   */
  default void onCommand(final T sender, @NotNull final String commandLabel, @NotNull final CommandParser parser) {

    throw new UnsupportedOperationException("This method should be correctly implemented.");
  }

  /**
   * Calling while command executed by specified sender
   *
   * @param sender       The command sender but will automatically convert to specified instance
   * @param commandLabel The command prefix (/quickshop = qs, /shop = shop)
   * @param cmdArgs      The command arguments
   *
   * @deprecated This method is deprecated, please use {@link #onCommand(T, String, CommandParser)}
   * instead.
   */
  @Deprecated(since = "4.2.0.0")
  default void onCommand(final T sender, @NotNull final String commandLabel, @NotNull final String[] cmdArgs) {

    throw new UnsupportedOperationException("This method is deprecated, please use onCommand(T sender, @NotNull String commandLabel, @NotNull CommandParser parser) instead.");
  }

  @Nullable
  default List<String> onTabComplete_Internal(@NotNull final T sender, @NotNull final String commandLabel, @NotNull final String[] cmdArg) {

    final StringJoiner joiner = new StringJoiner(" ");
    for(final String s : cmdArg) {
      joiner.add(s);
    }
    final CommandParser parser = new CommandParser(joiner.toString(), false);
    try {
      return onTabComplete(sender, commandLabel, parser);
    } catch(final UnsupportedOperationException ignore) {
      try {
        return onTabComplete(sender, commandLabel, parser.getArgs().toArray(new String[0]));
      } catch(final UnsupportedOperationException ignored) {
        return Collections.emptyList();
      }
    }
  }

  /**
   * Calling while sender trying to tab-complete
   *
   * @param sender       The command sender but will automatically convert to specified instance
   * @param commandLabel The command prefix (/quickshop = qs, /shop = shop)
   * @param parser       The command parser which include arguments and colon arguments
   *
   * @return Candidate list
   */
  @Nullable
  default List<String> onTabComplete(@NotNull final T sender, @NotNull final String commandLabel, @NotNull final CommandParser parser) {

    throw new UnsupportedOperationException("This method should be correctly implemented.");
  }

  /**
   * Calling while sender trying to tab-complete
   *
   * @param sender       The command sender but will automatically convert to specified instance
   * @param commandLabel The command prefix (/quickshop = qs, /shop = shop)
   * @param cmdArgs      The command arguments
   *
   * @return Candidate list
   *
   * @deprecated This method is deprecated, please use
   * {@link #onTabComplete(T, String, CommandParser)} instead.
   */
  @Deprecated(since = "4.2.0.0")
  default List<String> onTabComplete(@NotNull final T sender, @NotNull final String commandLabel, @NotNull final String[] cmdArgs) {

    throw new UnsupportedOperationException("This method is deprecated, please use onTabComplete(T sender, @NotNull String commandLabel, @NotNull CommandParser parser) instead.");
  }
}
